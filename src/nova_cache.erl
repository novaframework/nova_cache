-module(nova_cache).
-moduledoc """
Public API for the nova_cache library.

A general-purpose KV cache with pluggable adapters and distributed invalidation.
All time values are in milliseconds.

## Quick start

```erlang
%% In sys.config / app env:
{nova_cache, [
    {caches, #{
        user_lookup => #{adapter => nova_cache_ets, ttl_default => 60000, max_size => 10000}
    }}
]}.

%% In application code:
ok = nova_cache:put(user_lookup, <<"alice">>, #{role => admin}),
{ok, User} = nova_cache:get(user_lookup, <<"alice">>),
{ok, User} = nova_cache:fetch(user_lookup, <<"alice">>, fun() -> load_user() end).
```

## Failure model

Distributed invalidation is best-effort eventual. TTL is the correctness
backstop. See the Invalidation guide for the `invalidation => best_effort |
ttl_only | strict` knob and netsplit behaviour.

## Stability

`nova_cache` is NOT a dependency of nova core and must never become one.
""".

-export([
    get/2,
    get/3,
    put/3,
    put/4,
    fetch/3,
    fetch/4,
    delete/2,
    delete_many/2,
    invalidate/2,
    clear/1
]).

-type cache_name() :: atom().
-type key() :: binary().
-type value() :: term().
-type fetch_opts() :: #{
    ttl => non_neg_integer(),
    single_flight => boolean(),
    cache_errors => boolean() | {true, #{ttl => non_neg_integer()}},
    timeout => non_neg_integer()
}.
-type put_opts() :: #{ttl => non_neg_integer()}.

-export_type([cache_name/0, key/0, value/0, fetch_opts/0, put_opts/0]).

-spec get(cache_name(), key()) -> {ok, value()} | miss.
get(Name, Key) ->
    case nova_cache_registry:lookup(Name) of
        {ok, Adapter, State} ->
            case Adapter:get(Key, State) of
                {ok, V} -> {ok, V};
                miss -> miss;
                {error, _} -> miss
            end;
        {error, not_found} ->
            miss
    end.

-spec get(cache_name(), key(), Default :: value()) -> value().
get(Name, Key, Default) ->
    case get(Name, Key) of
        {ok, V} -> V;
        miss -> Default
    end.

-spec put(cache_name(), key(), value()) -> ok | {error, term()}.
put(Name, Key, Value) ->
    put(Name, Key, Value, #{}).

-spec put(cache_name(), key(), value(), put_opts()) -> ok | {error, term()}.
put(Name, Key, Value, Opts) ->
    case nova_cache_registry:lookup(Name) of
        {ok, Adapter, State} -> Adapter:put(Key, Value, Opts, State);
        {error, _} = E -> E
    end.

-spec fetch(cache_name(), key(), fun(() -> {ok, value()} | {error, term()})) ->
    {ok, value()} | {error, term()}.
fetch(Name, Key, Fun) ->
    fetch(Name, Key, Fun, #{}).

-spec fetch(cache_name(), key(), fun(() -> {ok, value()} | {error, term()}), fetch_opts()) ->
    {ok, value()} | {error, term()}.
fetch(Name, Key, Fun, Opts) ->
    case get(Name, Key) of
        {ok, V} ->
            {ok, V};
        miss ->
            case maps:get(single_flight, Opts, true) of
                true -> nova_cache_single_flight:load(Name, Key, Fun, Opts);
                false -> compute_and_store(Name, Key, Fun, Opts)
            end
    end.

-spec delete(cache_name(), key()) -> ok | {error, term()}.
delete(Name, Key) ->
    case nova_cache_registry:lookup(Name) of
        {ok, Adapter, State} ->
            R = Adapter:delete(Key, State),
            nova_cache_single_flight:invalidate_local(Name, Key),
            R;
        {error, _} = E ->
            E
    end.

-spec delete_many(cache_name(), [key()]) -> ok | {error, term()}.
delete_many(Name, Keys) ->
    case nova_cache_registry:lookup(Name) of
        {ok, Adapter, State} ->
            R =
                case erlang:function_exported(Adapter, delete_many, 2) of
                    true -> Adapter:delete_many(Keys, State);
                    false -> delete_each(Adapter, State, Keys)
                end,
            [nova_cache_single_flight:invalidate_local(Name, K) || K <- Keys],
            R;
        {error, _} = E ->
            E
    end.

-spec invalidate(cache_name(), key() | [key()]) -> ok | {error, term()}.
invalidate(Name, Key) when is_binary(Key) ->
    ok = delete(Name, Key),
    broadcast_invalidation(Name, {delete, Name, Key});
invalidate(Name, Keys) when is_list(Keys) ->
    ok = delete_many(Name, Keys),
    broadcast_invalidation(Name, {delete_many, Name, Keys}).

-spec clear(cache_name()) -> ok | {error, term()}.
clear(Name) ->
    logger:info(#{event => nova_cache_clear, name => Name}),
    case nova_cache_registry:lookup(Name) of
        {ok, Adapter, State} ->
            R = Adapter:clear(State),
            broadcast_invalidation(Name, {clear, Name}),
            R;
        {error, _} = E ->
            E
    end.

%% Internal

compute_and_store(Name, Key, Fun, Opts) ->
    case safe_apply(Fun) of
        {ok, V} = OK ->
            ok = put(Name, Key, V, ttl_opts(Opts)),
            OK;
        {error, _Reason} = Err ->
            _ = maybe_cache_error(Name, Key, Err, Opts),
            Err;
        Other ->
            {error, {bad_fun_return, Other}}
    end.

safe_apply(Fun) ->
    try Fun() of
        R -> R
    catch
        Class:Reason:Stack -> {error, {Class, Reason, Stack}}
    end.

ttl_opts(#{ttl := T}) -> #{ttl => T};
ttl_opts(_) -> #{}.

maybe_cache_error(Name, Key, Err, #{cache_errors := true}) ->
    put(Name, Key, Err, #{ttl => 1000});
maybe_cache_error(Name, Key, Err, #{cache_errors := {true, #{ttl := T}}}) ->
    put(Name, Key, Err, #{ttl => T});
maybe_cache_error(_, _, _, _) ->
    ok.

delete_each(_Adapter, _State, []) ->
    ok;
delete_each(Adapter, State, [K | Rest]) ->
    _ = Adapter:delete(K, State),
    delete_each(Adapter, State, Rest).

broadcast_invalidation(Name, Event) ->
    case application:get_env(nova_cache, invalidator, undefined) of
        undefined -> ok;
        Mod -> Mod:broadcast(Name, Event)
    end.
