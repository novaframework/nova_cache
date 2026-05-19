-module(nova_cache_ets_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("common_test/include/ct.hrl").

all() ->
    [
        max_size_evicts_lru,
        sweep_purges_expired_rows,
        strict_invalidation_requires_ttl_default
    ].

init_per_suite(Config) ->
    _ = application:load(nova_cache),
    application:set_env(nova_cache, caches, #{}),
    {ok, _} = application:ensure_all_started(nova_cache),
    Config.

end_per_suite(_) ->
    ok = application:stop(nova_cache),
    ok.

max_size_evicts_lru(_) ->
    Spec = #{
        adapter => nova_cache_ets, ttl_default => infinity, max_size => 2, sweep_interval => 50
    },
    {ok, _} = nova_cache_sup:start_cache(lru_cache, Spec),
    ok = nova_cache:put(lru_cache, <<"a">>, 1),
    ok = nova_cache:put(lru_cache, <<"b">>, 2),
    ok = nova_cache:put(lru_cache, <<"c">>, 3),
    timer:sleep(100),
    Hits = lists:filter(
        fun({_, R}) -> R =/= miss end,
        [{K, nova_cache:get(lru_cache, K)} || K <- [<<"a">>, <<"b">>, <<"c">>]]
    ),
    2 = length(Hits),
    ok = nova_cache_sup:stop_cache(lru_cache).

sweep_purges_expired_rows(_) ->
    Spec = #{
        adapter => nova_cache_ets,
        ttl_default => 50,
        max_size => infinity,
        sweep_interval => 100
    },
    {ok, _} = nova_cache_sup:start_cache(sweep_cache, Spec),
    ok = nova_cache:put(sweep_cache, <<"k">>, gone),
    timer:sleep(200),
    miss = nova_cache:get(sweep_cache, <<"k">>),
    ok = nova_cache_sup:stop_cache(sweep_cache).

strict_invalidation_requires_ttl_default(_) ->
    Spec = #{adapter => nova_cache_ets, invalidation => strict},
    {error, _} = (catch nova_cache_sup:start_cache(strict_cache, Spec)).
