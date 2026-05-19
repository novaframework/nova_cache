-module(nova_cache_invalidator).
-moduledoc """
Behaviour for nova_cache distributed-invalidation transports.

A transport ships invalidation events between nodes so that `delete/2`,
`delete_many/2`, and `clear/1` operations are reflected across the cluster.

## Guarantees

Best-effort eventual delivery. TTL is the correctness backstop. A node that is
netsplit, GC-paused, or just-joined may miss events; the documented model is
`invalidation => best_effort | ttl_only | strict` (configured per cache).

## Event shapes

- `{delete, Name :: atom(), Key :: binary()}`
- `{delete_many, Name :: atom(), [binary()]}`
- `{clear, Name :: atom()}`

Transports must deliver these payloads unchanged to the local handler on every
subscribed node.
""".

-type event() ::
    {delete, atom(), binary()}
    | {delete_many, atom(), [binary()]}
    | {clear, atom()}.

-export_type([event/0]).

-callback start_link(Opts :: map()) -> {ok, pid()} | {error, term()}.
-callback subscribe(Name :: atom(), Handler :: fun((event()) -> any())) -> ok | {error, term()}.
-callback broadcast(Name :: atom(), Event :: event()) -> ok | {error, term()}.
