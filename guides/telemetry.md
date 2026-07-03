<!--
SPDX-FileCopyrightText: 2024 bolty contributors
SPDX-License-Identifier: Apache-2.0
-->

# Telemetry

Bolty emits [`:telemetry`](https://hexdocs.pm/telemetry) events for the query and
connection lifecycle, so you can wire query latency, pool health, and error rates
into your own metrics/tracing without wrapping every call site.

Attach a handler at application start:

```elixir
:telemetry.attach_many(
  "bolty-logger",
  [
    [:bolty, :query, :stop],
    [:bolty, :query, :exception],
    [:bolty, :connect],
    [:bolty, :disconnect]
  ],
  &MyApp.Telemetry.handle_event/4,
  nil
)
```

Durations are in `:native` time units — convert with
`System.convert_time_unit(duration, :native, :millisecond)`.

## Query events

`Bolty.query/4`, `Bolty.query!/4`, `Bolty.query_many/4`, and `Bolty.query_many!/4`
wrap the server round-trip in a [`:telemetry.span/3`](https://hexdocs.pm/telemetry/telemetry.html#span/3),
emitting the standard start/stop/exception trio under `[:bolty, :query]`.

| Event | Measurements | Metadata |
| --- | --- | --- |
| `[:bolty, :query, :start]` | `:monotonic_time`, `:system_time` | `:db_system`, `:db_statement`, `:db_instance`, `:telemetry_span_context` |
| `[:bolty, :query, :stop]` | `:monotonic_time`, `:duration` | `:db_system`, `:db_statement`, `:db_instance`, `:result`, (`:error`), `:telemetry_span_context` |
| `[:bolty, :query, :exception]` | `:monotonic_time`, `:duration` | `:db_system`, `:db_statement`, `:db_instance`, `:kind`, `:reason`, `:stacktrace`, `:telemetry_span_context` |

Metadata keys:

- `:db_system` — always `"neo4j"`.
- `:db_statement` — the Cypher statement string.
- `:db_instance` — the target database from the `:db` option, or `nil` for the
  server default.
- `:result` — `:ok` or `:error`, a coarse outcome status you can map straight onto
  a span status. A server-side failure (e.g. a Cypher error) is an `:error`
  **`:stop`**, not an `:exception`; the `:exception` event fires only when a call
  raises (e.g. a `DBConnection.ConnectionError` on a checkout/queue timeout).
- `:error` — present only when `:result` is `:error`: the `%Bolty.Error{}` (or a
  `%DBConnection.ConnectionError{}`) returned to the caller.

Query **parameters are not included** in metadata — they routinely carry secrets.

## Connection events

| Event | Measurements | Metadata |
| --- | --- | --- |
| `[:bolty, :connect]` | `:duration` | `:db_system`, `:bolt_version`, `:server_version`, `:connection_id` |
| `[:bolty, :disconnect]` | `:system_time` | `:db_system`, `:connection_id` |

## Mapping to OpenTelemetry

The `:db_*` metadata keys mirror the OpenTelemetry
[database semantic conventions](https://opentelemetry.io/docs/specs/semconv/database/)
(dots become underscores, since `:telemetry` metadata keys are atoms), so a bridge
such as [`opentelemetry_telemetry`](https://hex.pm/packages/opentelemetry_telemetry)
can translate an event into a span with minimal glue:

| Bolty metadata | OpenTelemetry attribute |
| --- | --- |
| `:db_system` | `db.system` (`"neo4j"`) |
| `:db_statement` | `db.statement` |
| `:db_instance` | `db.instance` |

These follow the classic `db.*` names; recent semconv revisions rename some
(`db.statement` → `db.query.text`, `db.instance` → `db.namespace`) — map them in
your handler if you target the newer spec.

`[:bolty, :connect]` fires once a connection is fully established (HELLO/LOGON
complete); `:duration` covers config parsing, the TCP/TLS connect, and the Bolt
handshake. `[:bolty, :disconnect]` fires when DBConnection tears a connection down.
