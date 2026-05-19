-module(nova_cache_sup).
-moduledoc false.

-behaviour(supervisor).

-export([start_link/0, init/1, start_cache/2, stop_cache/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 10, period => 60},
    Registry = #{
        id => nova_cache_registry,
        start => {nova_cache_registry, start_link, []},
        restart => permanent,
        shutdown => 5000,
        type => worker
    },
    Caches = configured_caches(),
    {ok, {SupFlags, [Registry | Caches]}}.

start_cache(Name, Spec) ->
    supervisor:start_child(?MODULE, child_spec(Name, Spec)).

stop_cache(Name) ->
    case supervisor:terminate_child(?MODULE, Name) of
        ok -> supervisor:delete_child(?MODULE, Name);
        Error -> Error
    end.

configured_caches() ->
    Caches = application:get_env(nova_cache, caches, #{}),
    maps:fold(fun(Name, Spec, Acc) -> [child_spec(Name, Spec) | Acc] end, [], Caches).

child_spec(Name, Spec) ->
    Adapter = maps:get(adapter, Spec, nova_cache_ets),
    #{
        id => Name,
        start => {Adapter, start_link, [Name, Spec]},
        restart => permanent,
        shutdown => 5000,
        type => worker
    }.
