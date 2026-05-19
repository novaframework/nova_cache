-module(nova_cache_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

all() ->
    [
        get_returns_miss_for_unknown_key,
        get_with_default_returns_default,
        put_then_get_returns_value,
        delete_removes_key,
        delete_many_removes_listed_keys,
        clear_removes_all_keys,
        fetch_computes_on_miss,
        fetch_returns_cached_on_hit,
        fetch_caches_error_when_opted_in,
        fetch_does_not_cache_error_by_default,
        ttl_expires_value
    ].

init_per_suite(Config) ->
    _ = application:load(nova_cache),
    application:set_env(nova_cache, caches, #{
        suite => #{
            adapter => nova_cache_ets,
            ttl_default => 60_000,
            sweep_interval => 50
        }
    }),
    {ok, _} = application:ensure_all_started(nova_cache),
    Config.

end_per_suite(_Config) ->
    ok = application:stop(nova_cache),
    ok.

init_per_testcase(_, Config) ->
    nova_cache:clear(suite),
    Config.

end_per_testcase(_, _) ->
    ok.

get_returns_miss_for_unknown_key(_) ->
    miss = nova_cache:get(suite, <<"nope">>).

get_with_default_returns_default(_) ->
    default = nova_cache:get(suite, <<"nope">>, default).

put_then_get_returns_value(_) ->
    ok = nova_cache:put(suite, <<"k">>, ~"value"),
    {ok, ~"value"} = nova_cache:get(suite, <<"k">>).

delete_removes_key(_) ->
    ok = nova_cache:put(suite, <<"k">>, 1),
    ok = nova_cache:delete(suite, <<"k">>),
    miss = nova_cache:get(suite, <<"k">>).

delete_many_removes_listed_keys(_) ->
    ok = nova_cache:put(suite, <<"a">>, 1),
    ok = nova_cache:put(suite, <<"b">>, 2),
    ok = nova_cache:put(suite, <<"c">>, 3),
    ok = nova_cache:delete_many(suite, [<<"a">>, <<"b">>]),
    miss = nova_cache:get(suite, <<"a">>),
    miss = nova_cache:get(suite, <<"b">>),
    {ok, 3} = nova_cache:get(suite, <<"c">>).

clear_removes_all_keys(_) ->
    ok = nova_cache:put(suite, <<"a">>, 1),
    ok = nova_cache:put(suite, <<"b">>, 2),
    ok = nova_cache:clear(suite),
    miss = nova_cache:get(suite, <<"a">>),
    miss = nova_cache:get(suite, <<"b">>).

fetch_computes_on_miss(_) ->
    {ok, 42} = nova_cache:fetch(suite, <<"k">>, fun() -> {ok, 42} end),
    {ok, 42} = nova_cache:get(suite, <<"k">>).

fetch_returns_cached_on_hit(_) ->
    ok = nova_cache:put(suite, <<"k">>, 99),
    {ok, 99} = nova_cache:fetch(suite, <<"k">>, fun() -> {ok, 0} end).

fetch_caches_error_when_opted_in(_) ->
    Err = {error, boom},
    Err = nova_cache:fetch(suite, <<"e">>, fun() -> Err end, #{cache_errors => true}),
    {ok, Err} = nova_cache:get(suite, <<"e">>).

fetch_does_not_cache_error_by_default(_) ->
    Err = {error, nope},
    Err = nova_cache:fetch(suite, <<"e2">>, fun() -> Err end),
    miss = nova_cache:get(suite, <<"e2">>).

ttl_expires_value(_) ->
    ok = nova_cache:put(suite, <<"k">>, fresh, #{ttl => 100}),
    {ok, fresh} = nova_cache:get(suite, <<"k">>),
    timer:sleep(150),
    miss = nova_cache:get(suite, <<"k">>).
