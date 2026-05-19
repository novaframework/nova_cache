-module(nova_cache_single_flight).
-moduledoc false.

-export([load/4, invalidate_local/2]).

-define(TABLE, nova_cache_single_flight).

-spec load(atom(), binary(), fun(), map()) -> {ok, term()} | {error, term()}.
load(Name, Key, Fun, Opts) ->
    _ = ensure_table(),
    Ref = make_ref(),
    InsertKey = {Name, Key},
    case ets:insert_new(?TABLE, {InsertKey, self(), Ref, []}) of
        true ->
            compute_and_publish(Name, Key, Fun, Opts, InsertKey);
        false ->
            wait_for_leader(InsertKey, Opts)
    end.

invalidate_local(Name, Key) ->
    _ = ensure_table(),
    ets:delete(?TABLE, {Name, Key}),
    ok.

%% Internal

ensure_table() ->
    case ets:info(?TABLE) of
        undefined ->
            try
                ets:new(?TABLE, [named_table, public, set, {read_concurrency, true}])
            catch
                error:badarg -> ?TABLE
            end;
        _ ->
            ?TABLE
    end.

compute_and_publish(Name, Key, Fun, Opts, InsertKey) ->
    Result = compute(Name, Key, Fun, Opts),
    notify_and_clear(InsertKey, Result),
    Result.

compute(Name, Key, Fun, Opts) ->
    case safe_apply(Fun) of
        {ok, V} = OK ->
            ok = nova_cache:put(Name, Key, V, ttl_opts(Opts)),
            OK;
        {error, _} = Err ->
            _ = cache_error_if_opted_in(Name, Key, Err, Opts),
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

cache_error_if_opted_in(Name, Key, Err, #{cache_errors := true}) ->
    nova_cache:put(Name, Key, Err, #{ttl => 1000});
cache_error_if_opted_in(Name, Key, Err, #{cache_errors := {true, #{ttl := T}}}) ->
    nova_cache:put(Name, Key, Err, #{ttl => T});
cache_error_if_opted_in(_, _, _, _) ->
    ok.

notify_and_clear(InsertKey, Result) ->
    case ets:lookup(?TABLE, InsertKey) of
        [{InsertKey, _Leader, _Ref, Waiters}] ->
            ets:delete(?TABLE, InsertKey),
            _ = [W ! {nova_cache_sf_result, InsertKey, Result} || W <- Waiters],
            ok;
        [] ->
            ok
    end.

wait_for_leader(InsertKey, Opts) ->
    Timeout = maps:get(timeout, Opts, 5000),
    case register_waiter(InsertKey) of
        ok ->
            receive
                {nova_cache_sf_result, InsertKey, Result} -> Result
            after Timeout -> {error, single_flight_timeout}
            end;
        no_leader ->
            {error, single_flight_lost_leader}
    end.

register_waiter(InsertKey) ->
    case ets:lookup(?TABLE, InsertKey) of
        [{InsertKey, Leader, Ref, Waiters}] ->
            New = {InsertKey, Leader, Ref, [self() | Waiters]},
            case
                ets:select_replace(?TABLE, [
                    {
                        {InsertKey, Leader, Ref, Waiters}, [], [{const, New}]
                    }
                ])
            of
                1 -> ok;
                0 -> register_waiter(InsertKey)
            end;
        [] ->
            no_leader
    end.
