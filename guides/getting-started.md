# Getting Started

## Installation

```erlang
{deps, [
    {nova_cache, {git, "https://github.com/novaframework/nova_cache.git", {branch, "main"}}}
]}.
```

## Configuration

Declare your caches in `sys.config`:

```erlang
{nova_cache, [
    {caches, #{
        user_lookup => #{
            adapter => nova_cache_ets,
            ttl_default => 60_000,
            max_size => 10_000,
            sweep_interval => 60_000,
            invalidation => best_effort
        }
    }},
    {invalidator, nova_cache_invalidator_pg}
]}.
```

One supervised process per declared cache starts under `nova_cache_sup`.

## Reading and writing

```erlang
ok = nova_cache:put(user_lookup, <<"alice">>, User).
{ok, User} = nova_cache:get(user_lookup, <<"alice">>).
User = nova_cache:get(user_lookup, <<"alice">>, #{role => guest}).
```

## get-or-compute

```erlang
{ok, User} = nova_cache:fetch(user_lookup, <<"alice">>, fun() ->
    case load_from_db(<<"alice">>) of
        {ok, U} -> {ok, U};
        not_found -> {error, not_found}
    end
end).
```

Concurrent callers for the same key are deduplicated via single-flight.
Disable with `#{single_flight => false}` if you need pass-through semantics.

## Negative caching

Off by default. Opt in per call:

```erlang
%% short negative TTL (5 seconds):
nova_cache:fetch(user_lookup, <<"alice">>, F, #{cache_errors => {true, #{ttl => 5_000}}}).
```

## Invalidation across the cluster

```erlang
ok = nova_cache:invalidate(user_lookup, <<"alice">>).
```

The configured invalidator transport broadcasts the event to every subscribing
node. Each node purges its local copy on receipt. Delivery is best-effort
eventual; see the Invalidation guide for the failure model.
