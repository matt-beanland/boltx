<!--
SPDX-FileCopyrightText: 2025 bolty contributors
SPDX-License-Identifier: Apache-2.0
-->

# Public API & compatibility boundary

This page states what bolty considers **public** — the surface covered by
semantic versioning — versus what is **internal** and may change in any release.
If you depend on something not listed here as public, treat it as liable to
change without a major-version bump.

## Public API

These modules and their documented functions are the supported surface:

- **`Bolty`** — the entrypoint: `start_link/1`, `child_spec/1`, `query/4`,
  `query!/4`, `query_many/4`, `query_many!/4`, `transaction/4`, `rollback/2`,
  and `connection_info/1`.
- **`Bolty.Response`** — the result struct returned by `query/4`
  (`results`, `fields`, `records`, `plan`, `notifications`, `stats`, `profile`,
  `type`, `bookmark`). It implements `Enumerable` (iterating **rows**), and
  `Bolty.Response.first/1` returns the first row.
- **`Bolty.Error`** — the error struct. Its `:bolt` field is a
  `%{code: ..., message: ...}` map; match on that for server error details.
- **`Bolty.Policy`** — the resolved per-connection capability struct, read via
  `connection_info/1`.
- **`Bolty.Types.*`** — the value types decoded from / encoded to Neo4j:
  `Node`, `Relationship`, `UnboundRelationship`, `Path`, `TimeWithTZOffset`,
  `DateTimeWithTZOffset`, `Vector`, `Point` (plus standard Elixir `Time`,
  `NaiveDateTime`, `Duration`).
- **`Bolty.ResponseEncoder`** and **`Bolty.ResponseEncoder.Json`**
  (with the `Jason`/`Poison` back-ends) — JSON encoding of responses.
- **`Bolty.PackStream.Packer`** — you may `@derive` it on your own structs to
  control how they serialize into query parameters, e.g.
  `@derive [{Bolty.PackStream.Packer, fields: [:name]}]`.

## Internal

Everything marked `@moduledoc false` is internal and unsupported for direct
use. That includes:

```text
Bolty.Client               Bolty.Connection
Bolty.BoltProtocol.*       Bolty.BoltProtocol.Versions
Bolty.Policy.Resolver      Bolty.ConnectionInfo
Bolty.PackStream           (unpacker, markers)
Bolty.Query                Bolty.Queries
Bolty.Utils.*
```

Construct queries through `Bolty.query/4` and `Bolty.query_many/4` rather than
building those structs directly.

## The `connection_info/1` contract

`Bolty.connection_info/1` returns a map with:

- `:bolt_version` — the negotiated Bolt version as a string (e.g. `"5.8"`)
- `:server_version` — the server product string (e.g. `"Neo4j/5.26.27"`)
- `:policy` — the resolved `%Bolty.Policy{}`

## Consumer compatibility contract

These shapes are load-bearing for downstream consumers (notably
[`ash_neo4j`](https://github.com/diffo-dev/ash_neo4j)) and will not change
without a major-version bump:

- `%Bolty.Response{}` keeps its `results` field.
- `%Bolty.Types.Vector{}` keeps its `data` field.
- `%Bolty.Error{}` keeps `:bolt` as a `%{code, message}` map.
- `connection_info/1` keeps its `:policy` and `:server_version` keys.
- `%Bolty.Policy{}` keeps its `cypher_25` and `dynamic_labels` fields (new
  fields may be added).
