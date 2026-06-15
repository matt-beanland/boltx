<!--
SPDX-FileCopyrightText: 2024 bolty contributors
SPDX-License-Identifier: Apache-2.0
-->

# Bolty

[![Module Version](https://img.shields.io/hexpm/v/bolty)](https://hex.pm/packages/bolty)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen)](https://hexdocs.pm/bolty/)
[![License](https://img.shields.io/hexpm/l/bolty)](https://github.com/diffo-dev/bolty/blob/master/LICENSES/Apache-2.0.txt)
[![REUSE status](https://api.reuse.software/badge/github.com/diffo-dev/bolty)](https://api.reuse.software/info/github.com/diffo-dev/bolty)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/diffo-dev/bolty)

`Bolty` is an Elixir driver for [Neo4j](https://neo4j.com/developer/graph-database/)/Bolt Protocol, forked from `Boltx` and now developed independently.

- Supports Neo4j 5.26.27 LTS and Neo4j 2026.05
- Supports Bolt versions: 5.0/5.1/5.2/5.3/5.4/5.6/5.7/5.8/6.0
- Supports transactions, prepared queries, streaming, pooling and more via DBConnection
- Automatic decoding and encoding of Elixir values

Documentation: [https://hexdocs.pm/bolty](https://hexdocs.pm/bolty)

## Features

| Feature               | Implemented |
| --------------------- | ------------ |
| Querys                | YES          |
| Transactions          | YES          |
| Stream capabilities   | NO           |
| Routing               | NO           |

## Usage

Add :bolty to your dependencies:

```elixir
def deps() do
  [
    {:bolty, "~> 0.1.0"}
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

# Pin to a specific Bolt version:
opts = [versions: [5.4]] ++ opts

# Offer multiple versions as ranges (handshake has 4 slots — ranges cover more):
opts = [versions: [{5, 6..8}, {5, 0..4}]] ++ opts

iex> {:ok, conn} = Bolty.start_link(opts)
{:ok, #PID<0.237.0>}

iex> Bolty.query!(conn, "return 1 as n") |> Bolty.Response.first()
%{"n" => 1}

# Commit is performed automatically if everythings went fine
Bolty.transaction(conn, fn conn ->
  result = Bolty.query!(conn, "CREATE (m:Movie {title: "Matrix"}) RETURN m")
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

By default the scheme is `bolt+s`

| URI        | Description                                | TLSOptions              |
|------------|--------------------------------------------|-------------------------|
| neo4j      | Unsecured                                  | []                      |
| neo4j+s    | Secured with full certificate              | [verify: :verify_none]  |
| neo4j+ssc  | Secured with self-signed certificate       | [verify: :verify_peer]  |
| bolt       | Unsecured                                  | []                      |
| bolt+s     | Secured with full certificate              | [verify: :verify_none]  |
| bolt+ssc   | Secured with self-signed certificate       | [verify: :verify_peer]  |

## Negotiated capabilities

Bolty negotiates the highest mutually-supported Bolt version during connection. The outcome determines which protocol behaviours are active for the lifetime of that connection. Call `Bolty.connection_info/1` to inspect what was negotiated:

```elixir
iex> Bolty.connection_info(conn)
%{
  bolt_version: 5.8,
  server_version: "Neo4j/5.26.27",
  policy: %Bolty.Policy{
    datetime: :evolved,
    notifications_field: :notifications_disabled_classifications,
    gql_errors: true,
    vectors: false
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

### Restricting the negotiated version

By default Bolty offers all supported Bolt versions to the server and the highest common version wins. Use the `:versions` option to constrain the offer if your application requires specific capabilities:

```elixir
# Require GQL-compliant errors (Bolt 5.7+)
opts = [versions: [{5, 7..8}]] ++ opts

# Require the renamed notification field (Bolt 5.6+)
opts = [versions: [{5, 6..8}]] ++ opts

# Target a single known version
opts = [versions: [5.4]] ++ opts

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

As certain versions of Bolt may be compatible with specific functionalities while others can undergo significant changes, tags are employed to facilitate version-specific testing. Some of these tags include:

- `:core` (Included in all executions).
- `:bolt_version_{{specific version}}` (Tag to run the test on a specific version, for example, for 5.2: `:bolt_version_5_2`, for version 1: `:bolt_version_1_0)`.
- `bolt_{major version}_x`  (Tag to run on all minor versions of a major version, for example, for 5: `:bolt_5_x`, for all minor versions of 4:: `:bolt_4_x`).
- `:last_version` (Tag to run the test only on the latest version).

By default, all tags are disabled except the `:core` tag. To enable the tags, it is necessary to configure the following environment variables:

- `BOLT_VERSIONS`: **Deprecated** — use the `:versions` connection option instead. Still supported as a testing escape hatch (e.g. `BOLT_VERSIONS=5.4 mix test`), but will emit a warning at runtime.
- `BOLT_TCP_PORT`:  You can configure the port with the environment variable (BOLT_TCP_PORT=7688).

#### Version matrix
To run the suite against every supported Bolt version, use `mix test.matrix` (see `mix help test.matrix`). It reads `BOLT_TCP_PORT` for Bolt 5.x servers and `BOLT_6_TCP_PORT` for Bolt 6.x.

## Acknowledgments

Thanks to [Florin Patrascu](https://github.com/florinpatrascu) for [bolt_sips](https://github.com/florinpatrascu/bolt_sips) and [Luis Sagastume](https://github.com/sagastume) for [boltx](https://github.com/sagastume/boltx).