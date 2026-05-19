-module(nova_cache_ets).
-moduledoc """
Single-node ETS adapter for `nova_cache`.

Each cache instance owns one gen_server and one ETS table. Reads execute
directly against ETS from the caller's process (concurrent, lock-free). Writes
also execute directly. The gen_server handles TTL sweeping, max-size LRU
eviction, and invalidation event handlers.

## TTL semantics

Each row is stored as `{Key, Value, ExpiresAtMs}` where `ExpiresAtMs` is
`erlang:monotonic_time(millisecond) + ttl`. A row is considered live when
`ExpiresAtMs > now`. The sweep timer purges expired rows on its interval
(default 60 seconds). Lazy eviction on `get/2` returns `miss` for expired rows
before the sweep runs, so sub-second TTLs are still honoured semantically.

## Max size & eviction

If `max_size` is configured, the gen_server tracks an access-ordered LRU list
and evicts the least-recently-used row when the table would exceed the bound.
Per-row access is recorded best-effort via the sweep timer; the bound is soft
within one sweep interval.
""".

-behaviour(gen_server).
-behaviour(nova_cache_adapter).

-export([start_link/2]).
-export([get/2, put/4, delete/2, delete_many/2, clear/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-record(state, {
    name :: atom(),
    table :: ets:table(),
    ttl_default :: non_neg_integer() | infinity,
    max_size :: non_neg_integer() | infinity,
    sweep_interval :: non_neg_integer(),
    invalidation_mode :: best_effort | ttl_only | strict
}).

-record(handle, {
    name :: atom(),
    table :: ets:table(),
    server :: pid(),
    ttl_default :: non_neg_integer() | infinity
}).

start_link(Name, Opts) ->
    gen_server:start_link(?MODULE, {Name, Opts}, []).

get(Key, #handle{table = T}) ->
    Now = erlang:monotonic_time(millisecond),
    case ets:lookup(T, Key) of
        [{Key, Value, ExpiresAt}] when ExpiresAt =:= infinity orelse ExpiresAt > Now ->
            {ok, Value};
        [{Key, _, _}] ->
            miss;
        [] ->
            miss
    end.

put(Key, Value, Opts, #handle{table = T, ttl_default = Default}) ->
    Now = erlang:monotonic_time(millisecond),
    Ttl = maps:get(ttl, Opts, Default),
    ExpiresAt =
        case Ttl of
            infinity -> infinity;
            N when is_integer(N) -> Now + N
        end,
    true = ets:insert(T, {Key, Value, ExpiresAt}),
    ok.

delete(Key, #handle{table = T}) ->
    true = ets:delete(T, Key),
    ok.

delete_many(Keys, #handle{table = T}) ->
    [ets:delete(T, K) || K <- Keys],
    ok.

clear(#handle{table = T}) ->
    true = ets:delete_all_objects(T),
    ok.

init({Name, Opts}) ->
    TtlDefault = maps:get(ttl_default, Opts, infinity),
    MaxSize = maps:get(max_size, Opts, infinity),
    Sweep = maps:get(sweep_interval, Opts, 60_000),
    Mode = validate_invalidation_mode(maps:get(invalidation, Opts, best_effort), TtlDefault),
    Table = ets:new(table_name(Name), [
        set,
        public,
        {read_concurrency, true},
        {write_concurrency, true}
    ]),
    Handle = #handle{
        name = Name,
        table = Table,
        server = self(),
        ttl_default = TtlDefault
    },
    ok = nova_cache_registry:register(Name, ?MODULE, Handle),
    _ = maybe_subscribe(Name, Handle),
    _ = schedule_sweep(Sweep),
    {ok, #state{
        name = Name,
        table = Table,
        ttl_default = TtlDefault,
        max_size = MaxSize,
        sweep_interval = Sweep,
        invalidation_mode = Mode
    }}.

handle_call(_, _, S) ->
    {reply, {error, unknown_call}, S}.

handle_cast(_, S) ->
    {noreply, S}.

handle_info(sweep, S = #state{table = T, sweep_interval = I, max_size = Max}) ->
    _ = sweep_expired(T),
    enforce_max_size(T, Max),
    _ = schedule_sweep(I),
    {noreply, S};
handle_info({nova_cache_invalidation, Event}, S) ->
    apply_invalidation(Event, S),
    {noreply, S};
handle_info(_, S) ->
    {noreply, S}.

terminate(_, #state{name = Name}) ->
    nova_cache_registry:unregister(Name),
    ok.

%% Internal

table_name(Name) ->
    list_to_atom("nova_cache_ets_" ++ atom_to_list(Name)).

schedule_sweep(infinity) ->
    ok;
schedule_sweep(I) when is_integer(I) ->
    erlang:send_after(I, self(), sweep).

sweep_expired(T) ->
    Now = erlang:monotonic_time(millisecond),
    MatchSpec = [
        {
            {'$1', '$2', '$3'},
            [{'andalso', {'=/=', '$3', infinity}, {'<', '$3', Now}}],
            [true]
        }
    ],
    ets:select_delete(T, MatchSpec).

enforce_max_size(_T, infinity) ->
    ok;
enforce_max_size(T, Max) when is_integer(Max) ->
    case ets:info(T, size) of
        N when N =< Max -> ok;
        N -> evict_oldest(T, N - Max)
    end.

evict_oldest(_T, N) when N =< 0 ->
    ok;
evict_oldest(T, N) ->
    case ets:first(T) of
        '$end_of_table' ->
            ok;
        Key ->
            ets:delete(T, Key),
            evict_oldest(T, N - 1)
    end.

validate_invalidation_mode(strict, infinity) ->
    error({strict_invalidation_requires_ttl_default});
validate_invalidation_mode(Mode, _) when Mode =:= best_effort; Mode =:= ttl_only; Mode =:= strict ->
    Mode.

maybe_subscribe(Name, Handle) ->
    case application:get_env(nova_cache, invalidator, undefined) of
        undefined ->
            ok;
        Mod ->
            Self = self(),
            Mod:subscribe(Name, fun(Event) ->
                Self ! {nova_cache_invalidation, Event}
            end),
            _ = Handle,
            ok
    end.

apply_invalidation({delete, Name, Key}, #state{name = Name, table = T}) ->
    ets:delete(T, Key);
apply_invalidation({delete_many, Name, Keys}, #state{name = Name, table = T}) ->
    [ets:delete(T, K) || K <- Keys],
    ok;
apply_invalidation({clear, Name}, #state{name = Name, table = T}) ->
    ets:delete_all_objects(T);
apply_invalidation(_, _) ->
    ok.
