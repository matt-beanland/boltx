<!--
SPDX-FileCopyrightText: 2025 bolty contributors
SPDX-License-Identifier: Apache-2.0
-->

# Bolty

[![Module Version](https://img.shields.io/hexpm/v/bolty)](https://hex.pm/packages/bolty)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen)](https://hexdocs.pm/bolty/)
[![License](https://img.shields.io/hexpm/l/bolty)](https://github.com/diffo-dev/bolty/blob/master/LICENSES/Apache-2.0.txt)
[![REUSE status](https://api.reuse.software/badge/github.com/diffo-dev/bolty)](https://api.reuse.software/info/github.com/diffo-dev/bolty)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/diffo-dev/bolty)

`Bolty` is an Elixir driver for [Neo4j](https://neo4j.com/developer/graph-database/)/Bolt Protocol, forked from `Boltx` and now developed independently.

- Supports Neo4j 5.26.28 LTS and Neo4j 2026.06
- Supports Bolt versions: 5.0/5.1/5.2/5.3/5.4/5.6/5.7/5.8/6.0
- Supports transactions, prepared queries, streaming, pooling and more via DBConnection
- Automatic decoding and encoding of Elixir values

Documentation: [https://hexdocs.pm/bolty](https://hexdocs.pm/bolty)

## Features

| Feature               | Implemented |
| --------------------- | ------------ |
| Queries               | YES          |
| Transactions          | YES          |
| Streaming             | YES — `Bolty.stream/4` (lazy, server-side backpressure) |
| Routing               | Partial — server-side routing (SSR) for `neo4j://` schemes; no autodiscovery/failover |

## Usage

Add :bolty to your dependencies:

```elixir
def deps() do
  [
    {:bolty, "~> 0.3.0"}
  ]
end
```

Using the latest version.

```elixir

opts = [
    hostname: "127.0.0.1",
    auth: [username: "neo4j", password: "password"],
    user_agent: "boltyTest/1",
    pool_size: 15,
    max_overflow: 3,
    prefix: :default
]

# Pin to a specific Bolt version (versions are strings; floats are deprecated):
opts = [versions: ["5.4"]] ++ opts

# Offer multiple versions as ranges (handshake has 4 slots — ranges cover more):
opts = [versions: [{5, 6..8}, {5, 0..4}]] ++ opts

iex> {:ok, conn} = Bolty.start_link(opts)
{:ok, #PID<0.237.0>}

iex> Bolty.query!(conn, "return 1 as n") |> Bolty.Response.first()
%{"n" => 1}

# Commit is performed automatically if everything went fine
Bolty.transaction(conn, fn conn ->
  result = Bolty.query!(conn, "CREATE (m:Movie {title: 'Matrix'}) RETURN m")
end)

# Lazily stream a large result in batches (server-side backpressure).
# Must be enumerated inside a transaction; :fetch_size sets the batch size.
Bolty.transaction(conn, fn conn ->
  conn
  |> Bolty.stream("MATCH (n) RETURN n", %{}, fetch_size: 500)
  |> Stream.flat_map(& &1.results)
  |> Enum.each(&IO.inspect/1)
end)

```

### Set it up in an app

Add the configuration to the corresponding files for each environment or to your config/config.ex.
> #### Name of process
>
> The process name must be defined in your configuration


```elixir
import Config

config :bolty, Bolt,
  uri: "bolt://localhost:7687",
  auth: [username: "neo4j", password: "password"],
  user_agent: "boltyTest/1",
  pool_size: 15,
  max_overflow: 3,
  prefix: :default,
  name: Bolt
```

Add Bolty to the application's main monitoring tree and let OTP manage it.

```elixir
# lib/n4_d/application.ex

defmodule N4D.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      %{
        id: Bolty,
        start: {Bolty, :start_link, [Application.get_env(:bolty, Bolt)] },
      }
    ]

    opts = [strategy: :one_for_one, name: N4D.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```
Or

```elixir
children = [
  {Bolty, Application.get_env(:bolty, Bolt)}
]
```
Now you can run query with the name you set

```elixir
iex> Bolty.query!(Bolt, "return 1 as n") |> Bolty.Response.first()
%{"n" => 1}
```


### URI schemes

By default the scheme is `bolt+s`, which performs full certificate verification.

| URI        | Description                            | Default TLS behaviour                                             |
|------------|---------------------------------------|------------------------------------------------------------------|
| neo4j      | Unsecured                             | no TLS                                                            |
| neo4j+s    | Secured, full certificate verification | `verify: :verify_peer` against the system CA store, with SNI + hostname verification |
| neo4j+ssc  | Secured, self-signed / trust-all      | `verify: :verify_none` (encryption only, no verification)        |
| bolt       | Unsecured                             | no TLS                                                            |
| bolt+s     | Secured, full certificate verification | `verify: :verify_peer` against the system CA store, with SNI + hostname verification |
| bolt+ssc   | Secured, self-signed / trust-all      | `verify: :verify_none` (encryption only, no verification)        |

The `+s` defaults use the OS trust store via `:public_key.cacerts_get/0`, which
verifies Neo4j Aura and other public-CA certificates out of the box. In a minimal
container without an OS trust store, add [`castore`](https://hex.pm/packages/castore)
and pass `ssl_opts: [cacertfile: CAStore.file_path()]`.

Any `:ssl_opts` you pass are merged **over** these defaults, so you can override
verification (e.g. `ssl_opts: [verify: :verify_none]` for local development) or
point at a private CA (`ssl_opts: [cacertfile: "..."]`).

```elixir
# Default TLS: bolt+s / neo4j+s verify the server cert against the OS trust
# store — works out of the box for Neo4j Aura and other public CAs.
{:ok, conn} =
  Bolty.start_link(
    scheme: "neo4j+s",
    hostname: "xxxx.databases.neo4j.io",
    auth: [username: "neo4j", password: System.fetch_env!("NEO4J_PASSWORD")]
  )

# Self-signed / internal certificate: use +ssc (encrypted, no verification).
Bolty.start_link(scheme: "bolt+ssc", hostname: "neo4j.internal", auth: [username: "neo4j", password: "..."])

# Verify against your own private CA instead of the OS trust store.
Bolty.start_link(
  scheme: "bolt+s",
  hostname: "neo4j.internal",
  ssl_opts: [cacertfile: "/etc/ssl/my-ca.pem"],
  auth: [username: "neo4j", password: "..."]
)
```

Generating and installing the server's certificates is Neo4j-side configuration —
see Neo4j's [SSL framework](https://neo4j.com/docs/operations-manual/current/security/ssl-framework/)
docs. Neo4j Aura and other managed offerings present public-CA certificates, so
`+s` needs no setup.

> **Self-signed certificates and `+s`:** Erlang's `:ssl` (which bolty uses)
> rejects a **self-signed *server* certificate** under full verification — the
> peer cert is flagged `:selfsigned_peer` — even if you pass that same cert as the
> CA via `ssl_opts: [cacertfile: ...]`, and regardless of its `basicConstraints`.
> (OpenSSL is more lenient, so `openssl verify` succeeding does **not** mean `+s`
> will.) `+s` needs a **genuine chain**: a CA certificate that signed a *distinct*
> server leaf — the server presents the leaf (which isn't self-signed), and you
> trust the CA via `cacertfile`. For a single self-signed cert (a typical local /
> dev box) use **`+ssc`** instead, which encrypts without verifying.
>
> To use `+s` with your own PKI, create a root CA and a server cert signed by it:
>
> ```bash
> # 1. root CA (self-signed, CA:TRUE)
> openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 3650 \
>   -subj "/CN=My Neo4j CA" -addext "basicConstraints=critical,CA:TRUE"
> # 2. server key + CSR, then sign the leaf with the CA (CA:FALSE, serverAuth, SAN)
> openssl req -newkey rsa:2048 -nodes -keyout server.key -out server.csr -subj "/CN=neo4j.internal"
> openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 825 \
>   -out server.crt -extfile <(printf "basicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\nsubjectAltName=IP:192.168.4.50")
> # Neo4j serves server.crt + server.key; bolty trusts ca.crt:
> #   scheme: "bolt+s", ssl_opts: [cacertfile: "ca.crt"]
> ```

> **Changed in 0.3.0:** `+s`/`+ssc` verification was previously inverted, and
> `+s` did no server authentication. `+s` now verifies by default, and explicit
> `:ssl_opts` are no longer silently overridden. Pin `0.2.1` if you depend on the
> old behaviour.

### Named-zone datetimes

A Neo4j `datetime()` carrying a named zone (e.g. `"Europe/Berlin"`) is resolved
into an Elixir `DateTime` when decoded, which requires a configured
`:time_zone_database`. Bolty deliberately bundles none — that global is the host
application's to own — so configure one:

```elixir
# add {:tz, "~> 0.28"} (or {:tzdata, "~> 1.1"}) to your deps, then in config:
config :elixir, :time_zone_database, Tz.TimeZoneDatabase
```

Without a database, decoding such a value does not crash — the query returns a
clear `{:error, %Bolty.Error{code: :time_zone_database_not_configured}}`.
Integer-offset datetimes (`DateTimeWithTZOffset`) need no database.

## Negotiated capabilities

Bolty negotiates the highest mutually-supported Bolt version during connection. The outcome determines which protocol behaviours are active for the lifetime of that connection. Call `Bolty.connection_info/1` to inspect what was negotiated:

```elixir
iex> Bolty.connection_info(conn)
%{
  bolt_version: "5.8",
  server_version: "Neo4j/5.26.28",
  policy: %Bolty.Policy{
    datetime: :evolved,
    notifications_field: :notifications_disabled_classifications,
    gql_errors: true,
    vectors: false,
    cypher_5: true,
    cypher_25: false,
    dynamic_labels: true
  }
}
```

### Capability table

| Capability | Bolt 5.0 – 5.5 | Bolt 5.6 | Bolt 5.7 – 5.8 | Bolt 6.0+ |
|---|---|---|---|---|
| DateTime encoding | evolved (UTC-aware) | evolved | evolved | evolved |
| Notification filter field | `notifications_disabled_categories` | `notifications_disabled_classifications` | `notifications_disabled_classifications` | `notifications_disabled_classifications` |
| GQL-compliant errors | No — `code`/`message` keys | No | Yes — `neo4j_code`/`description` keys | Yes |
| Auth handshake | In HELLO (Bolt 5.0 only) | LOGON | LOGON | LOGON |
| Vector type | No | No | No | Yes |

The `policy` struct is the single source of truth for version-driven behaviour inside the driver. User code should not need to branch on `bolt_version` directly — check `connection_info/1` if you need to gate application-level features on negotiated capabilities.

### Server capability flags

`cypher_5`, `cypher_25` and `dynamic_labels` are derived from the **server** version reported at HELLO (not the negotiated Bolt version), so they capture Cypher-language capabilities that vary by Neo4j release rather than by wire protocol:

| Flag | `true` when | Example feature |
|---|---|---|
| `cypher_5` | server speaks `CYPHER 5` (Neo4j ≥ 5.0) — every currently supported server | prefix queries with `CYPHER 5` |
| `cypher_25` | server supports the `CYPHER 25` selector (Neo4j ≥ 2025.06) | `CYPHER 25` syntax |
| `dynamic_labels` | dynamic labels/types in **pattern position** (Neo4j ≥ 5.26) — a Cypher 5 feature; superset of `cypher_25` | `MATCH (n:$($label))`, `CREATE (n:$($label))` |

So a `5.26.x` server resolves to `dynamic_labels: true, cypher_25: false`, while a `2026.06` server has both `true`. These flags are only meaningful in the policy resolved after HELLO; they default to `false` beforehand.

> **Scope of `dynamic_labels`:** it covers the **pattern-position** form only — node labels and relationship types in `MATCH`/`CREATE`/`MERGE`. The `WHERE n:$(expr)` label-**predicate** form is a separate **Cypher 25** feature: gate it on `cypher_25`, not `dynamic_labels`. (It errors under `CYPHER 5` even on a `2026.x` server, and is unsupported on `5.26.x`.)

### Restricting the negotiated version

By default Bolty offers all supported Bolt versions to the server and the highest common version wins. Use the `:versions` option to constrain the offer if your application requires specific capabilities:

```elixir
# Require GQL-compliant errors (Bolt 5.7+)
opts = [versions: [{5, 7..8}]] ++ opts

# Require the renamed notification field (Bolt 5.6+)
opts = [versions: [{5, 6..8}]] ++ opts

# Target a single known version (a string; a float like `5.4` is deprecated)
opts = [versions: ["5.4"]] ++ opts

# Offer two disjoint ranges when you want broad compatibility but must skip 5.5
opts = [versions: [{5, 6..8}, {5, 0..4}]] ++ opts
```

The handshake has four slots; range tuples let you cover a span of minor versions in a single slot. If the server cannot satisfy the offered range(s) the connection will fail with a version-negotiation error rather than silently falling back to an unsupported version.

## Vector embeddings (Bolt 6.0+)

`Bolty.Types.Vector` represents a typed list of floating-point values for embedding and similarity search. It is available on connections negotiated at Bolt 6.0 (Neo4j 2026.05+). Attempting to send a `Vector` over an older connection raises `Bolty.Error` with code `:vector_requires_bolt_6`.

```elixir
alias Bolty.Types.Vector

# Ensure a Bolt 6.0 connection
{:ok, conn} = Bolty.start_link([versions: [6.0]] ++ opts)

embedding = Vector.new(:float32, [0.1, 0.2, 0.3])

# Pass as a parameter — round-trips the value over the wire:
[%{"v" => result}] = Bolty.query!(conn, "RETURN $v AS v", %{v: embedding})

# Storing vectors as node properties requires Neo4j Enterprise Edition.
```

Supported element types:
- `:float32` — IEEE-754 single precision (4 bytes per element)
- `:float64` — IEEE-754 double precision (8 bytes per element)

## Telemetry

Bolty emits [`:telemetry`](https://hexdocs.pm/telemetry) events for the query
(`[:bolty, :query, :start | :stop | :exception]`), streaming
(`[:bolty, :stream, :start | :fetch | :stop]`), and connection
(`[:bolty, :connect | :disconnect]`) lifecycle, so you can attach query latency,
pool health, and error-rate metrics without wrapping every call site. See the
[Telemetry guide](guides/telemetry.md) for the full event/measurement/metadata
reference.

## Contributing

### Getting Started

Neo4j uses the Bolt protocol for communication and query execution. You can find the official documentation for Bolt here: [Bolt Documentation](https://neo4j.com/docs/bolt/current).

It is crucial to grasp various concepts before getting started, with the most important ones being:

- [PackStream](https://neo4j.com/docs/bolt/current/packstream/): The syntax layer for the Bolt messaging protocol.
- [Bolt Protocol](https://neo4j.com/docs/bolt/current/bolt/): The application protocol for database queries via a database query language.
  - Bolt Protocol handshake specification
  - Bolt Protocol message specification
  - Structure Semantics

It is advisable to use the specific terminology from the official documentation and official drivers to ensure consistency with this implementation.

### Test

The suite is split into **unit** and **integration** tests:

- Plain `mix test` runs the unit suite only — no Neo4j required — so a contributor without Docker can run and add tests. This includes the PackStream round-trip property tests.
- DB-dependent tests are tagged `:integration` and are excluded by default. They run automatically when a server is configured (any `BOLT_TCP_PORT` or `BOLT_VERSIONS`, as CI and `mix test.matrix` set), or explicitly with `mix test --include integration`. For a local server: `BOLT_TCP_PORT=7687 mix test`.

As certain versions of Bolt may be compatible with specific functionalities while others can undergo significant changes, tags are employed to facilitate version-specific testing. Some of these tags include:

- `:core` (a version-agnostic integration test — runs at whatever version is negotiated).
- `:bolt_version_{{specific version}}` (Tag to run the test on a specific version, for example, for 5.2: `:bolt_version_5_2`, for version 1: `:bolt_version_1_0)`.
- `bolt_{major version}_x`  (Tag to run on all minor versions of a major version, for example, for 5: `:bolt_5_x`, for all minor versions of 4:: `:bolt_4_x`).
- `:last_version` (Tag to run the test only on the latest version).

When a server is configured, `:core` tests run and the version tags are disabled by default. To enable specific version tags, configure the following environment variables:

- `BOLT_VERSIONS`: selects the Bolt version the **test suite** negotiates and which version tags run (e.g. `BOLT_VERSIONS=5.4 mix test`). This is a test-suite convenience only — configure the driver itself with the `:versions` connection option.
- `BOLT_TCP_PORT`: the port the **test suite** connects to (default 7687). Configure the driver itself with the `:port` connection option.

#### Version matrix
To run the suite against every supported Bolt version, use `mix test.matrix` (see `mix help test.matrix`). It reads `BOLT_TCP_PORT` for Bolt 5.x servers and `BOLT_6_TCP_PORT` for Bolt 6.x.

## Acknowledgments

Thanks to [Florin Patrascu](https://github.com/florinpatrascu) for [bolt_sips](https://github.com/florinpatrascu/bolt_sips) and [Luis Sagastume](https://github.com/sagastume) for [boltx](https://github.com/sagastume/boltx).
