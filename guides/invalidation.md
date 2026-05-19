# Invalidation

`nova_cache` ships cluster invalidation as a swappable transport behaviour.
The default transport is `nova_cache_invalidator_pg`, built on `pg`.

## Guarantee

**Best-effort eventual.** TTL is the correctness backstop. A node that is
netsplit, GC-paused, or just-joined may miss broadcasts and serve stale data
until the row expires.

## Per-cache mode

Configured via the `invalidation` key in the cache spec:

| Mode          | Behaviour                                                                |
| ------------- | ------------------------------------------------------------------------ |
| `best_effort` | Subscribe to broadcasts; serve stale on miss. Default.                   |
| `ttl_only`    | Skip broadcasts entirely; rely solely on TTL.                            |
| `strict`      | Best-effort plus refuses to start without `ttl_default`. Bounds staleness.|

## Failure mode: a node misses a broadcast

It serves stale data until the row's TTL elapses. If the row was written with
`ttl => infinity`, it serves stale data indefinitely. This is the design.

For workloads where "indefinitely stale" is unacceptable, use `strict` mode
and a finite `ttl_default`.

## Failure mode: a node joins late

On join, the node's caches start empty. They subscribe and start receiving
broadcasts immediately. There is no backfill of historical events. Existing
entries on the joining node (e.g. after a netsplit heal) are not purged
automatically in `best_effort` mode -- if you need that, run `clear/1` from
your application's join handler.

## Writing a new transport

1. `-behaviour(nova_cache_invalidator).`
2. Implement `start_link/1`, `subscribe/2`, `broadcast/2`.
3. Deliver event payloads to subscribed handlers on every node.
4. Set `{nova_cache, [{invalidator, your_module}]}` in `sys.config`.

Transports must deliver events unchanged. They may drop events on failure
without compromising correctness, because TTL is the backstop.
