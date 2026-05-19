# Telemetry

`nova_cache` emits OpenTelemetry counters and spans when `opentelemetry_api`
is available at runtime. The dependency is optional; callers without it still
build and run.

## Counters

| Name                | Attributes              |
| ------------------- | ----------------------- |
| `nova_cache.hit`    | `cache.name`            |
| `nova_cache.miss`   | `cache.name`            |
| `nova_cache.evict`  | `cache.name`, `reason`  |

`reason` is `ttl` (lazy expiry on get), `sweep` (periodic sweeper), or
`max_size` (LRU eviction).

## Spans

| Name                  | Attributes                                  |
| --------------------- | ------------------------------------------- |
| `nova_cache.fetch`    | `cache.name`, `cache.key.length`, `result`  |
| `nova_cache.put`      | `cache.name`, `cache.key.length`            |
| `nova_cache.invalidate` | `cache.name`, `cache.invalidate.scope`    |

`result` is `hit | miss | loaded | error`.

## Enabling

Add `opentelemetry_api` to your project's `rebar.config`. `nova_cache`
detects the module at runtime and starts emitting events. No configuration on
`nova_cache` itself is required.

The OpenTelemetry-aware sibling library `opentelemetry_nova_cache` (planned
for v0.2) will install the trace/metric pipeline; until then, configure it in
your application's own OpenTelemetry setup.
