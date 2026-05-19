-module(nova_cache_invalidator_pg).
-moduledoc """
`pg`-based distributed invalidation transport for nova_cache.

Each cache subscribes to the process group `{nova_cache, Name}`. Broadcasts
deliver the event message to every member of the group across the cluster.

This transport depends on the standard `pg` module (no extra dependencies).
""".

-behaviour(nova_cache_invalidator).
-behaviour(gen_server).

-export([start_link/1, subscribe/2, broadcast/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(SCOPE, nova_cache_pg).

-record(state, {handlers = #{} :: #{atom() => [fun((nova_cache_invalidator:event()) -> any())]}}).

start_link(_Opts) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

subscribe(Name, Handler) ->
    gen_server:call(?MODULE, {subscribe, Name, Handler}).

broadcast(Name, Event) ->
    Members = pg:get_members(?SCOPE, {nova_cache, Name}),
    [erlang:send(Pid, {nova_cache_pg_event, Event}, [noconnect, nosuspend]) || Pid <- Members],
    ok.

init([]) ->
    _ = ensure_scope(),
    {ok, #state{}}.

handle_call({subscribe, Name, Handler}, _From, S = #state{handlers = H}) ->
    Existing = maps:get(Name, H, []),
    NewH = H#{Name => [Handler | Existing]},
    case Existing of
        [] -> ok = pg:join(?SCOPE, {nova_cache, Name}, self());
        _ -> ok
    end,
    {reply, ok, S#state{handlers = NewH}};
handle_call(_, _, S) ->
    {reply, {error, unknown_call}, S}.

handle_cast(_, S) ->
    {noreply, S}.

handle_info({nova_cache_pg_event, Event}, S = #state{handlers = H}) ->
    Name = event_name(Event),
    Handlers = maps:get(Name, H, []),
    [safe_apply(F, Event) || F <- Handlers],
    {noreply, S};
handle_info(_, S) ->
    {noreply, S}.

%% Internal

ensure_scope() ->
    case pg:start(?SCOPE) of
        {ok, _Pid} -> ok;
        {error, {already_started, _}} -> ok
    end.

event_name({delete, N, _}) -> N;
event_name({delete_many, N, _}) -> N;
event_name({clear, N}) -> N.

safe_apply(F, E) ->
    try F(E) of
        _ -> ok
    catch
        _:_ -> ok
    end.
