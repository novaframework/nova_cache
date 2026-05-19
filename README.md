# nova_cache

General-purpose KV cache library for the Nova ecosystem.

`nova_cache` is **not** a dependency of Nova core and must never become one.

## Quick start

```erlang
%% sys.config
{nova_cache, [
    {caches, #{
        user_lookup => #{
            adapter => nova_cache_ets,
            ttl_default => 60_000,
            max_size => 10_000
        }
    }}
]}.

%% application code
ok = nova_cache:put(user_lookup, <<"alice">>, #{role => admin}),
{ok, User} = nova_cache:get(user_lookup, <<"alice">>),
{ok, User} = nova_cache:fetch(user_lookup, <<"alice">>, fun load_user/0).
```

## Adapters

| Adapter            | Status |
| ------------------ | ------ |
| `nova_cache_ets`   | v0.1   |
| `nova_cache_redis` | v0.2   |

## Invalidation transports

| Transport                   | Status |
| --------------------------- | ------ |
| `nova_cache_invalidator_pg` | v0.1   |

## Build

```sh
rebar3 compile
rebar3 dialyzer
rebar3 xref
```

## Test

```sh
rebar3 ct
rebar3 eunit
rebar3 mutate
```

## Documentation

See the [guides](guides/) directory.

## License

Apache-2.0.
