# Adapters

Adapters implement the `nova_cache_adapter` behaviour and own their own
storage process. The `State` returned from `start_link/2`-time registration is
opaque to `nova_cache` and passed back to every subsequent callback.

## Shipped adapters

### `nova_cache_ets`

In-process ETS table per cache. Direct concurrent reads and writes from the
caller's process. Periodic sweep purges expired rows. Soft `max_size`
enforced at sweep time with LRU-on-table-order eviction.

Configuration:

| Option           | Default      | Notes                                     |
| ---------------- | ------------ | ----------------------------------------- |
| `ttl_default`    | `infinity`   | Default TTL applied when `put` omits one. |
| `max_size`       | `infinity`   | Soft bound; evictions happen on sweep.    |
| `sweep_interval` | `60_000`     | Milliseconds.                             |
| `invalidation`   | `best_effort`| `best_effort | ttl_only | strict`.        |

`strict` mode refuses to start without `ttl_default`.

## Writing a new adapter

1. `-behaviour(nova_cache_adapter).`
2. Implement `start_link/2`, `get/2`, `put/4`, `delete/2`, `delete_many/2`, `clear/1`.
3. Optionally implement `get_many/2` and `put_many/2`.
4. Register with `nova_cache_registry:register(Name, ?MODULE, State)` from
   `init/1` so the public API can route calls.
5. Subscribe to invalidation events on startup if you want cluster
   propagation.

Adapter callbacks may execute in the caller's process or proxy through the
adapter's own gen_server. That's the adapter's choice; the contract is the
return values, not the process topology.
