-module(nova_cache_adapter).
-moduledoc """
Behaviour for nova_cache storage adapters.

Each adapter owns its own process (typically a gen_server) and holds an opaque
`State` that nova_cache passes back to subsequent callbacks verbatim. All time
values are in milliseconds.

## Callback contract

- `start_link/2` is invoked by `nova_cache_sup` to spin up the adapter process
  for a configured cache. It must register `State` with `nova_cache_registry`
  before returning so the public API can route calls.
- Fast-path reads (`get/2`) may execute in the caller's process without going
  through the adapter's gen_server, provided the adapter's data structures
  permit concurrent reads (ETS with `read_concurrency` is the canonical case).
- Writes (`put/4`, `delete/2`, `delete_many/2`, `clear/1`) may be either
  caller-process or gen_server-mediated at the adapter's discretion.

## Optional callbacks

- `get_many/2` and `put_many/2` are batching helpers. If an adapter does not
  implement them, nova_cache falls back to iterating the single-key callbacks.
""".

-type opts() :: #{atom() => term()}.
-type put_opts() :: #{ttl => non_neg_integer()}.
-type key() :: binary().
-type value() :: term().

-export_type([opts/0, put_opts/0, key/0, value/0]).

-callback start_link(Name :: atom(), Opts :: opts()) -> {ok, pid()} | {error, term()}.
-callback get(Key :: key(), State :: term()) -> {ok, value()} | miss | {error, term()}.
-callback put(Key :: key(), Value :: value(), Opts :: put_opts(), State :: term()) ->
    ok | {error, term()}.
-callback delete(Key :: key(), State :: term()) -> ok | {error, term()}.
-callback delete_many([key()], State :: term()) -> ok | {error, term()}.
-callback clear(State :: term()) -> ok | {error, term()}.

-callback get_many([key()], State :: term()) -> {ok, #{key() => value()}} | {error, term()}.
-callback put_many([{key(), value()}], State :: term()) -> ok | {error, term()}.

-optional_callbacks([get_many/2, put_many/2]).
