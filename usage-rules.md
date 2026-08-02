<!--
SPDX-FileCopyrightText: 2025 bolty contributors
SPDX-License-Identifier: Apache-2.0
-->

# AGENTS.md — bolty

> Status: v1 draft. Written primarily for agents that will **use** or **work on** bolty. Secondary audience: future maintainers (us) who need to remember why it is shaped the way it is. Expected to evolve.

## 1. What bolty is

`bolty` is an Elixir driver for [Neo4j](https://neo4j.com/), forked from [`boltx`](https://github.com/sagastume/boltx) and now developed independently — the codebases have diverged significantly over the past year. Upstream acknowledgment belongs to Luis Sagastume (`boltx`) and Florin Patrascu (`bolt_sips`).

- **Protocol**: Bolt 5.0 → 5.4, 5.6 → 5.8, with version negotiation at handshake time.
- **Server compatibility**: Neo4j 5.26.28 LTS (Bolt 5.0–5.4, 5.6–5.8), Neo4j 2026.06 (Bolt 6.0).
- **Pooling/transactions/prepared queries** via [`DBConnection`](https://hexdocs.pm/db_connection).
- **Hex package**: `:bolty` (current version in `mix.exs`).

## 2. When to use bolty — and when not to

**Use bolty when**:
- You need direct Cypher/Bolt access from Elixir with `DBConnection` pooling.
- You are speaking to Neo4j.
- You want to hand-write Cypher and deal in `Bolty.Types.*` structs.

**Do not use bolty when**:
- You want Ash-style resources, actions, policies on top of Neo4j — use `ash_neo4j`, which sits on top of bolty.
- (Streaming of large result sets *is* supported now — see `Bolty.stream/4` and Feature Support — so this is no longer a reason to reach past bolty.)
- You need **full cluster routing** — topology autodiscovery, read-replica load-balancing, or automatic failover (not implemented). Server-side routing (SSR) against a single configured member *is* supported; see the Clustering guide and Feature Support.

If in doubt: agents operating *inside an Ash application* should almost always be going through `ash_neo4j`. bolty is the right tool for driver-level work, tests, benchmarks, and building higher-level abstractions.

## 3. Quick start

```elixir
# Start a pool
{:ok, conn} =
  Bolty.start_link(
    uri: "bolt://localhost:7687",
    auth: [username: "neo4j", password: "password"],
    pool_size: 10
  )

# Query
Bolty.query!(conn, "RETURN 1 AS n") |> Bolty.Response.first()
# => %{"n" => 1}

# Transaction (commits on normal return, rolls back on raise or explicit rollback)
Bolty.transaction(conn, fn conn ->
  Bolty.query!(conn, "CREATE (m:Movie {title: $t}) RETURN m", %{t: "Matrix"})
end)
```

Supervised:

```elixir
children = [
  {Bolty, Application.get_env(:bolty, Bolt)}
]
Supervisor.start_link(children, strategy: :one_for_one)
```

`Bolty.child_spec/1` returns a `DBConnection` pool child spec — name it via the standard `:name` option.

## 4. Public API — what agents call

| Function | Purpose | Notes |
| --- | --- | --- |
| `Bolty.start_link(opts)` | Start a pooled connection | Returns `{:ok, pid}`. Delegates to `DBConnection.start_link`. |
| `Bolty.child_spec(opts)` | Supervisor child spec | For embedding in a supervision tree. |
| `Bolty.query(conn, cypher, params \\ %{}, opts \\ [])` | Run one query | Returns `{:ok, %Bolty.Response{}} \| {:error, %Bolty.Error{}}`. |
| `Bolty.query!/4` | Raising variant | Raises `Bolty.Error` on failure. |
| `Bolty.query_many/4`, `query_many!/4` | Run a batch of statements | Returns list of responses. |
| `Bolty.stream(conn, cypher, params \\ %{}, opts \\ [])` | Lazily stream a large result in batches | Returns a `DBConnection` stream of `%Bolty.Response{}` (one per batch). **Must be enumerated inside a `transaction/4`**. `:fetch_size` opt (default 1000). A mid-stream failure **raises** `%Bolty.Error{}` (streams have no error-tuple channel). |
| `Bolty.transaction(conn, fun, opts \\ [], extra \\ %{})` | Transaction | `extra` is threaded into the BEGIN message (see §7). |
| `Bolty.rollback(conn, reason)` | Explicit rollback | Delegates to `DBConnection.rollback/2`. |
| `Bolty.Response.first/1` | Grab the first result row | Returns a map `%{field => value}` or `nil`. |

**`params`** is a map of Cypher parameters. Most Elixir values pass through unchanged; `Bolty.Types.Point` is formatted specially (see §6). If you want to pass `TimeWithTZOffset` / `DateTimeWithTZOffset` into Cypher, call `format_param/1` yourself — only `Point` is auto-formatted at the top level today.

**`opts`** accepts per-query extras lifted into the Bolt `extra` map: `:bookmarks`, `:mode` (`"r"` / `"w"`), `:db`, `:tx_metadata`. Everything else flows through to `DBConnection`.

## 5. Connection options

Canonical option names (what `Bolty.Client.Config.new/1` actually reads):

| Option | Meaning | Default |
| --- | --- | --- |
| `:uri` | `<scheme>://<host>[:<port>]` — explicit `:hostname`/`:port`/`:scheme` win over the URI's components | `nil` |
| `:hostname` | Host | `"localhost"` |
| `:port` | Port | `7687` |
| `:scheme` | One of the schemes below | `"bolt+s"` |
| `:routing` | Enable server-side routing (SSR) — `HELLO routing` field. Boolean; overrides the scheme default (`neo4j*` → `true`, `bolt*` → `false`). A non-boolean is a `:invalid_routing` error. See the Clustering guide. | scheme-derived |
| `:auth` | `[username: ..., password: ...]` (`:username` required) | required |
| `:versions` | Bolt versions to negotiate. Accepts strings (`["5.4"]`) or range tuples (`[{5, 6..8}, {5, 0..4}]`); floats (`[5.4]`) are deprecated (can't distinguish `5.10` from `5.1`) but still accepted with a warning. Range tuples are preferred — the handshake has only 4 slots and ranges cover more per slot. Omit to use `Versions.latest_versions()`. `connection_info/1` reports the negotiated `bolt_version` as a string (`"5.8"`). | `Versions.latest_versions()` |
| `:user_agent` | Client identity string | `"bolty/<version>"` |
| `:notifications_minimum_severity` | Bolt 5.2+ | `nil` |
| `:notifications_disabled_categories` | Bolt 5.2–5.5 | `nil` |
| `:notifications_disabled_classifications` | Bolt 5.6+ (renamed field; also accepts old key) | `nil` |
| `:connect_timeout` | ms | `15_000` |
| `:ssl_opts` | `:ssl.tls_client_option()` list | merged with scheme-implied defaults |
| `:socket_options` | `:gen_tcp.connect_option()` list | `[mode: :binary, packet: :raw, active: false]` |
| `:capabilities` | Server-capability flags asserted by the caller, overriding what bolty infers from the `server` string — for a non-Neo4j or emulating server (`[cypher_25: true, cypher_features: [:disjoint_by]]`). Values replace rather than merge; only `:cypher_5`/`:cypher_25`/`:dynamic_labels`/`:cypher_features` are overridable, anything else is an `:invalid_capability` error. See §14. | `[]` |
| DBConnection opts (`:name`, `:pool_size`, `:max_overflow`, `:after_connect`, ...) | flow through | |

**Precedence is uniform**: explicit opts (`:hostname`/`:port`/`:scheme`) win over the corresponding `:uri` components. The driver reads no environment variables for connection config (the old `BOLT_USER`/`BOLT_PWD`/`BOLT_HOST`/`BOLT_TCP_PORT`/`BOLT_VERSIONS` were removed in 0.3.0 — pass `:auth`, `:hostname`, `:port`, `:versions` instead).

### URI schemes / TLS

| URI scheme | TLS | ssl_opts merge |
| --- | --- | --- |
| `neo4j`, `bolt` | off | — |
| `neo4j+s`, `bolt+s` | on | `verify: :verify_peer` (full cert verification against the OS trust store) |
| `neo4j+ssc`, `bolt+ssc` | on | `verify: :verify_none` (encrypted, but self-signed / trust-all) |

Default scheme when nothing is specified is `bolt+s`. Examples: public-CA/Aura → `Bolty.start_link(scheme: "neo4j+s", hostname: "xxxx.databases.neo4j.io", auth: [...])`; self-signed → `scheme: "bolt+ssc"`; private CA → `scheme: "bolt+s", ssl_opts: [cacertfile: "/etc/ssl/my-ca.pem"]`. User `:ssl_opts` merge over the scheme defaults.

**Self-signed gotcha:** Erlang `:ssl` rejects a **self-signed server cert** under `+s` (full verification) — reason `:selfsigned_peer` — even if you pass that cert as `ssl_opts: [cacertfile: <it>]`, and regardless of `basicConstraints`/`CA:TRUE`. (OpenSSL is lenient, so `openssl verify` passing ≠ `+s` works.) `+s` needs a real chain: a CA cert that signed a *distinct* server leaf (trust the CA via `cacertfile`). For a single self-signed cert (local/dev box), use **`+ssc`**.

## 6. Value mapping — Elixir ↔ Bolt/Neo4j

All in `Bolty.Types`:

- Graph: `Node`, `Relationship`, `UnboundRelationship`, `Path` (with `Path.graph/1` walking helper).
- Temporal (Bolt v2+): standard Elixir `Time`, `NaiveDateTime`, `Duration`; and `TimeWithTZOffset`, `DateTimeWithTZOffset` when you need integer-offset timezones. DateTime encoding is now policy-driven: the connection resolves a `%Bolty.Policy{datetime: :legacy | :evolved}` at HELLO and the packer emits the matching struct tag (0x46/0x66 legacy on Bolt ≤ 4.x, 0x49/0x69 evolved on Bolt 5.x) with the matching body semantics (legacy = local-wall-clock seconds; evolved = UTC-instant seconds). Unpacker handles both on decode. Resolved in 0.0.10 — issue [#10](https://github.com/diffo-dev/bolty/issues/10). `Duration` round-trip as a native Neo4j duration was broken in 0.0.7 and fixed through 0.0.8 (microseconds) and 0.0.9 (stored-as-string) — issues [#6](https://github.com/diffo-dev/bolty/issues/6) and [#8](https://github.com/diffo-dev/bolty/issues/8). A `Duration` is held at Elixir `Duration`'s **microsecond** precision, so Neo4j's nanosecond component is truncated on decode (e.g. `123456789ns` → `123456µs`) — an accepted, by-design limitation, since Elixir has no nanosecond duration type. JSON encoding via `Bolty.ResponseEncoder` renders durations to match Neo4j's own `toString(duration)` otherwise (integer whole seconds, negatives, `PT0S`).
- **Named-zone datetimes need a time zone database.** A `datetime()` carrying a zone id (e.g. `"Europe/Berlin"`) is resolved into an Elixir `DateTime` at decode time, which requires a configured `:time_zone_database`. bolty does **not** bundle one (it would commandeer the global config) — configure one in your app, e.g. `config :elixir, :time_zone_database, Tz.TimeZoneDatabase` (add `:tz` or `:tzdata` to your deps). Without one, decoding such a value returns a clear `{:error, %Bolty.Error{code: :time_zone_database_not_configured}}` rather than crashing. Integer-offset datetimes (`DateTimeWithTZOffset`) need no database.
- Spatial (Bolt v2+): `Point` — 2D/3D, cartesian/WGS-84. Construct via `Point.create(:cartesian | :wgs_84 | <srid>, x, y [, z])`.

`Path` has a quirk worth knowing: the Bolt protocol uses signed byte indices into the relationships list, but a raw `-1` comes through as `255`. `Path.graph/1` patches this explicitly. Flagged in the source as "oh dear"; keep the patch, do not "clean it up" without regression tests.

## 7. Response shape and iteration

`Bolty.Response`:

```elixir
%Bolty.Response{
  results: [%{field => value}, ...],   # zipped rows, usually what you want
  fields: [String.t()],
  records: [[raw_value, ...]],         # untransformed column-major rows
  plan:   nil | map,
  notifications: list,
  stats:  list | map,
  profile: nil | any,
  type:   nil | String.t(),
  bookmark: nil | String.t()
}
```

- `Bolty.Response.first/1` returns the first row (or `nil` on empty).
- `Enumerable` is implemented over `results` — `Enum.map(response, & &1)`, `Enum.count/1`, `for row <- response, do: ...` all work. Note `Enum.slice/2` on a non-empty response raises due to the custom `slice/1` returning `:error`; stick to `reduce`-backed calls if possible.

## 8. Transactions

```elixir
Bolty.transaction(conn, fn conn ->
  Bolty.query!(conn, "CREATE (n:Thing) RETURN n")
  # raise / rollback / normal return — DBConnection decides commit vs rollback
end, [], %{db: "mydb", mode: "w", tx_metadata: %{caller: "agent-me"}})
```

- 4th arg (`extra_parameters`) is threaded into the Bolt BEGIN message via `extra_parameters` opt. This is the only way to scope `:db`, `:mode`, `:tx_metadata`, `:bookmarks` to the whole transaction (per-query `opts` only apply to a single RUN).
- `Bolty.rollback(conn, reason)` inside the fun aborts and returns `{:error, reason}` from the outer call.
- On syntax/semantic errors the driver proactively sends `RESET` (Bolt ≥ 3.0) or `ACK_FAILURE` (< 3.0) to recover the session.

## 9. JSON encoding

`Bolty.ResponseEncoder.encode(data, :json)` turns anything containing `Bolty.Types.*` into a JSON string. Two-step and overridable:

1. Type → jsonable (protocol: `Bolty.ResponseEncoder.Json`) — implement your own `defimpl` for custom handling.
2. Jsonable → string — Elixir's built-in `JSON` (no external dep). bolty also ships `JSON.Encoder` implementations for `Bolty.Types.*`, so a result can be handed straight to `JSON.encode!/1`. (Requires Elixir 1.18+; `jason`/`poison` support was dropped in 0.3.0.)

## 10. Errors

`%Bolty.Error{module, code, bolt, packstream}` — a `defexception`. Known code atoms:

| Bolt error | Atom |
| --- | --- |
| `Neo.ClientError.Security.Unauthorized` | `:unauthorized` |
| `Neo.ClientError.Request.Invalid` | `:request_invalid` |
| `Neo.ClientError.Statement.SemanticError` | `:semantic_error` |
| `Neo.ClientError.Statement.SyntaxError` | `:syntax_error` |

Everything else becomes `:unknown`, with the raw map still available in `error.bolt`. Expand `@error_map` in `lib/bolty/error.ex` when a new code becomes worth pattern-matching on.

`error.bolt` always carries `:code` and `:message` — **`:message` is the server's diagnostic**, and what `Exception.message/1` returns. A GQL FAILURE (Bolt 5.7+, `policy.gql_errors`) adds:

| Key | What it is |
| --- | --- |
| `:gql_status` | GQLSTATUS code, e.g. `"42001"` |
| `:description` | the standard description of that status **class** — generic by design. Pair it with `:gql_status`; never read it as the diagnostic. On 5.26 a syntax error's description is the 50N42 boilerplate ("unexpected error … See debug log for details") while `:message` has the offending token and position. |
| `:diagnostic_record` | `_classification`, plus `_position` (line/column) on servers that send it — 2026.x does, 5.26 doesn't |
| `:cause` | the underlying failure, same shape recursively, often a more precise GQLSTATUS than the outer error |

The GQL keys are absent (not `nil`) on a pre-5.7 connection, so `Map.has_key?/2` distinguishes "this server doesn't speak GQL errors" from "it did and the field was empty".

## 11. Feature support matrix

| Capability | Status |
| --- | --- |
| Queries (RUN/PULL) | ✅ |
| Transactions (explicit + implicit) | ✅ |
| Pooling (DBConnection) | ✅ |
| Encoding/decoding of graph, temporal, spatial types | ✅ |
| TLS variants (full / self-signed / off) | ✅ |
| Notifications opt-out (Bolt 5.2+) | ✅ |
| Vector type pack/unpack (Bolt 6.0) | ✅ — issue [#13](https://github.com/diffo-dev/bolty/issues/13) |
| Negotiated capability flags via `connection_info/1` | ✅ — `cypher_5`/`cypher_25`/`dynamic_labels`/`cypher_features` + wire-level dims (see §14) |
| Caller-asserted capabilities for non-Neo4j / emulating servers | ✅ — `:capabilities` start option (see §14) |
| Streaming result sets (lazy, server-side backpressure) | ✅ — `Bolty.stream/4` inside a transaction; `:fetch_size` batches, `[:bolty, :stream, *]` telemetry |
| Server-side routing (SSR) against a configured cluster member | ✅ — `neo4j://` schemes / `:routing`; see the Clustering guide |
| Full cluster routing (topology autodiscovery, read-replica load-balancing, auto-failover) | ❌ — front with DNS/L4 LB + bookmarks, or use an official driver |
| Vector search (indexes, similarity ops) | ❌ — bolty exposes the type; search belongs to the query layer |

If an agent needs cluster routing beyond SSR (autodiscovery/load-balancing/failover), that is not bolty's job — surface the gap to Matt rather than working around it silently.

## 12. Running tests

Tests are version-tagged. Defaults run only `:core`; everything else is disabled unless you opt in with env vars and tags.

- Env vars (test suite only — the driver reads none of these): `BOLT_VERSIONS` (e.g. `"5.2"`) selects the negotiated version and version tags; `BOLT_TCP_PORT` (e.g. `7687`) sets the server port. The test helper bridges them into the `:versions` / `:port` connection options.
- Tags: `:core`, `:bolt_version_X_Y` (e.g. `:bolt_version_5_2`), `:bolt_X_x` (e.g. `:bolt_5_x`), `:last_version`.

Local server matrix via `docker-compose.yml`:

| Service | Image | Ports (host:container) | Bolt versions |
| --- | --- | --- | --- |
| `neo4j-bolt5` | `neo4j:5.26.27` | `7687:7687`, `7474:7474` | 5.0–5.4, 5.6–5.8 |
| `neo4j-bolt6` | `neo4j:2026.06` | `7689:7687`, `7475:7474` | 6.0 |

Ports and credentials (`neo4j / password`) match ash_neo4j's `docker-compose.yml`, so the two repos can share the same containers.

Use `mix test.matrix` to run the full version matrix. Requires Docker and docker-compose. Bolt 6.x runs on a separate port — point `BOLT_6_TCP_PORT` at the `neo4j-bolt6` service (`7689`).

## 13. Development loop

- Elixir `~> 1.18` (the built-in `JSON` module used for result encoding is 1.18+). `.tool-versions` pins the expected runtime.
- `mix format` — `.formatter.exs` configured.
- `mix credo` — `.credo.exs` tuned; keep warnings at 0.
- `mix dialyzer` — PLT adds `:mix`; `.dialyzer_ignore.exs` holds accepted noise.
- `mix docs` — ex_doc; README.md is the main page.
- `mix test --cover` / `mix coveralls` — 70% threshold gate.
- `mix test.matrix` — runs the full test suite once per supported Bolt version against a local Neo4j instance and prints a pass/fail summary. Respects `BOLT_TCP_PORT` (default 7687).
- `mix bench` (if present as an alias) — uses `benchee`, outputs via `benchee_html`; benchees live in `benchees/`.
- `mix git_ops.release` — bumps the version, prepends a `CHANGELOG.md` section from the conventional commits since the last tag, and creates the release commit + tag. Pass `--dry-run` to preview without writing. See §16.

## 14. Implementation notes (for maintainers)

Layering, top to bottom:

```
Bolty                      (top-level API; format_param dispatch, transaction wrap)
  └── Bolty.Connection     (DBConnection behaviour; version-aware init)
        └── Bolty.Client   (socket I/O, handshake, message send/receive)
              └── Bolty.BoltProtocol.*
                    ├── Message.*           (HELLO, LOGON, RUN, BEGIN, ...)
                    ├── MessageEncoder / MessageDecoder
                    ├── Versions
                    └── ServerResponse      (statement_result / pull_result records)
                    └── Bolty.PackStream.*  (Markers, Packer, Unpacker)
```

Init dispatch in `Bolty.Connection.do_init/3`:

- Bolt 5.0 → `HELLO`.
- Bolt ≥ 5.1 → `HELLO` then `LOGON` (auth split out of HELLO).

`handle_execute/4` always runs via `DBConnection.prepare_execute` — bolty does **not** use real prepared statements; `DBConnection.Query` is implemented as a no-op passthrough in `lib/bolty/query.ex`. `handle_prepare`/`handle_close` are trivial and `handle_status` is hardcoded to `:idle`, but `handle_declare`/`handle_fetch`/`handle_deallocate` now implement real server-side cursor streaming (RUN → PULL `{n, qid}` → DISCARD) behind `Bolty.stream/4`.

Fork posture: drift from boltx is minimised on purpose. When applying fixes, prefer surgical patches over refactors so upstream back-ports remain feasible.

Compliance goals: bolty aims for [REUSE](https://reuse.software/) compliance (licence metadata on every file, including deps handling). Currently non-compliant — tracked in issue [#12](https://github.com/diffo-dev/bolty/issues/12). Keep this in mind when adding new source files.

### Policy-driven packstream

Version-aware encoding lives in `%Bolty.Policy{}` — an internal struct resolved once at HELLO completion from `(bolt_version, server_version)` via `Bolty.Policy.Resolver`, stashed on both `Bolty.Connection` and `Bolty.Client` state, and threaded through every `pack/2` call as a second argument. Codecs pattern-match on policy fields and never read a version number directly; that is the acceptance criterion for any future dimension.

Policy is the driver's own distillation of negotiated facts about how Bolt and the server have evolved. It is internal, but surfaced read-only via `Bolty.connection_info/1` so consumers can gate behaviour on a flag instead of parsing version strings. Dimensions today:

**Wire-level** — derived from the negotiated Bolt version:

- `:datetime` — `:legacy` on Bolt ≤ 4.x (tags 0x46/0x66, local-wall-clock seconds) or `:evolved` on Bolt ≥ 5.0 (tags 0x49/0x69, UTC-instant seconds). Issue [#10](https://github.com/diffo-dev/bolty/issues/10).
- `:notifications_field` — HELLO field for disabled notification categories: `:notifications_disabled_categories` (Bolt ≤ 5.5) or `:notifications_disabled_classifications` (Bolt 5.6+).
- `:gql_errors` — `true` on Bolt 5.7+ (GQL-compliant FAILURE: `code` is renamed to `neo4j_code`, and `gql_status`/`description`/`diagnostic_record`/`cause` join the always-present `message`; see §10).
- `:vectors` — `true` on Bolt 6.0+ (Vector PackStream struct, issue [#13](https://github.com/diffo-dev/bolty/issues/13)).

**Server-capability** — derived from the HELLO `server` string, only meaningful in the post-HELLO policy (default `false` beforehand):

- `:cypher_5` — server speaks `CYPHER 5` (Neo4j ≥ 5.0).
- `:cypher_25` — server supports the `CYPHER 25` selector (Neo4j ≥ 2025.06).
- `:dynamic_labels` — dynamic labels/types in **pattern position** (`MATCH (n:$(expr))`, `CREATE`/`MERGE`, relationship types); a Cypher 5 feature (Neo4j ≥ 5.26), a strict superset of `:cypher_25`. Covers the pattern form only — the `WHERE n:$(expr)` label-**predicate** form is a separate **Cypher 25** feature, gated on `:cypher_25` (errors under `CYPHER 5` even where Cypher 25 is supported; unsupported on `5.26.x`).
- `:cypher_features` — a `MapSet` of named Cypher 25 features finer-grained than the language selector, tested by membership (`:disjoint_by in policy.cypher_features`). Today: `:disjoint_by`, `:vector_search_in_predicate`, `:vector_hfq` (all Neo4j ≥ 2026.06). Every member errors under a `CYPHER 5` prefix, so gate on `:cypher_25` as well when emitting an explicit selector.

**Overrides** — inference reads Neo4j's calendar release from the `server` string, which is only sound for a server that is Neo4j and reports its real version. A server emulating Cypher 25 on its own cadence, or pinning a Neo4j agent string over a different feature subset, gets the baseline (no Cypher flags, empty feature set); the caller states the truth with `capabilities: [cypher_25: true, cypher_features: [:disjoint_by]]` at `start_link/1`. Values replace rather than merge, so an override can withdraw a wrong inference as well as add a missing capability. Only the four server-capability flags are overridable — asserting a wire-level dimension fails the connection with `:invalid_capability`.

To add a dimension: add the field to `Bolty.Policy`, extend `Bolty.Policy.Resolver` with a pure `put_*/3` clause, and dispatch the relevant codec/behaviour on it — do **not** bypass the boundary by reading a version number directly. Remember to update the docs too: the README "Negotiated capabilities" section and §11/§14 here.

To add a **named Cypher feature** (the common case as Cypher 25 evolves toward GQL): add `{:feature_name, yyyymm}` to `@cypher_features` in the resolver, an entry to the `Bolty.Policy.cypher_feature/0` typedoc, and a row to the README table — never a new struct field. Probe the boundary against real servers (a `SyntaxError` on the release before, accepted on the release recorded) rather than taking it from the release notes.

## 15. Sharp edges / known quirks

- `@error_map` only covers four Neo bolt errors; everything else collapses to `:unknown`. Extend when you need finer-grained handling.
- `format_param/1` at the top level only rewrites `Point`. Temporal-with-offset structs pass through as-is; call their own `format_param/1` if you need Cypher-ready strings.
- A missing `:username` returns `{:error, %Bolty.Error{code: :missing_username}}` from the connect path (it no longer raises). (The old `BOLT_USER`/`BOLT_PWD`/`BOLT_HOST`/`BOLT_TCP_PORT`/`BOLT_VERSIONS` env-var config was removed in 0.3.0 — pass explicit options.)
- `start_link/1` options are validated against an allowlist (bolty's own `start_option()` keys plus whatever `DBConnection.available_start_options/0` reports for the installed `db_connection` version); an unrecognised key (e.g. a typo like `hostnam: "..."`, or the removed pre-P0-1 `:ssl` boolean — TLS is derived entirely from `:scheme` now) returns `{:error, %Bolty.Error{code: :invalid_option}}` instead of silently falling back to a default.

## 16. Commit format and changelog

Commits follow [Conventional Commits](https://www.conventionalcommits.org/). The type determines which section of the changelog the change appears under:

| Type | Changelog section |
| --- | --- |
| `feat` | Features |
| `fix` | Bug Fixes |
| `perf` | Performance |
| `refactor` | Refactoring |
| `chore` | Chores |
| `docs` | Documentation |
| `test` | Testing |
| `ci` | CI/CD |
| `style` | Style |
| `revert` | Reverts |

Append `!` or include `BREAKING CHANGE:` in the footer for breaking changes — these are bolded in the changelog.

**Examples:**

```
feat: add Bolt 6.0 handshake support
fix: prevent timeout on idle connections under heavy load
chore: drop support for Neo4j 3.x and 4.x (Bolt 1.0–4.4)
```

**Changelog workflow:**

Releases are cut with [`git_ops`](https://hex.pm/packages/git_ops) (configured in
`config/dev.exs`), consistent with the other diffo-dev repos. It derives the next
version from the conventional commits since the last `v`-prefixed tag, writes the
`CHANGELOG.md` section, bumps `@version` in `mix.exs` and the dep snippet in
`README.md`, then commits and tags.

```sh
# Preview the next version + changelog without writing anything
mix git_ops.release --dry-run

# Cut the release: bump version, update CHANGELOG.md + README, commit, tag
mix git_ops.release

# Push the release commit and tag
git push && git push --tags
```

**Bump rules:** `git_ops` follows semver — `feat` bumps the minor, `fix`/`perf`/etc.
bump the patch, and a breaking change (`!` or `BREAKING CHANGE:`) bumps the major.
Pre-1.0 this still applies (e.g. a feature takes `0.1.0 → 0.2.0`). The release inserts
its section after the `<!-- changelog -->` marker in `CHANGELOG.md`; everything below
the marker is preserved history.

**Bootstrapping note:** for the very first `git_ops` release on a fresh project, run
`mix git_ops.release --initial` to establish the baseline tag. bolty already has tags
(`v0.1.0`), so a plain `mix git_ops.release` computes from there.

## 17. Issues (GitHub)

Tracked live on GitHub — see [open issues](https://github.com/diffo-dev/bolty/issues) rather than a snapshot here (which only goes stale). No open issues at the time of writing.

Recent work shipped in **v0.2.0**: the `cypher_5`/`cypher_25`/`dynamic_labels` policy flags (#47–#49) and the type-hygiene / dialyzer + warnings-as-errors CI gate (#50). For closed history and rationale, browse the tracker or the [`CHANGELOG`](./CHANGELOG.md).

## 18. Licensing and REUSE

bolty is Apache License 2.0 and is [REUSE](https://reuse.software/)-compliant. The compliance scheme — decided together with the maintainers and documented here so future contributors don't need to re-derive it:

- **Licence**: Apache-2.0 throughout. bolty derives from `boltx` (Luis Sagastume) which derives from `bolt_sips` (Florin Patrascu), both Apache-2.0. Upstream attribution lives in `NOTICE`; per-file headers carry the collective `bolty contributors` claim on our own modifications. Relicensing away from Apache-2.0 is not on the table — we don't own the upstream code and the patent grant is load-bearing for a protocol driver.
- **Per-file header template** (hash-comment languages — Elixir, YAML, shell, etc.):
  ```
  # SPDX-FileCopyrightText: 2025 bolty contributors
  # SPDX-License-Identifier: Apache-2.0
  ```
  For Markdown use HTML-comment form so GitHub renders it as nothing:
  ```html
  <!--
  SPDX-FileCopyrightText: 2025 bolty contributors
  SPDX-License-Identifier: Apache-2.0
  -->
  ```
  For shell scripts, the shebang stays on line 1; the header goes on lines 2–3.
- **When adding a new file**: apply the appropriate header on creation. `reuse lint` runs in CI (see `.github/workflows/ci.yml` → `reuse` job) and will fail a PR that ships an unheadered file.
- **Files that can't take inline headers** (JSON, `mix.lock`, terse dotfiles) are declared in `REUSE.toml` at the repo root. Add a new entry rather than hacking the comment syntax.
- **`LICENSES/Apache-2.0.txt`** is the canonical SPDX licence text — don't modify it. The root `LICENSE` mirrors it for GitHub's project-metadata scraper.
- **`NOTICE`** is the attribution chain — extend it only if the project derives from a new upstream.

`bolty contributors` is a collective attribution label; the authoritative list of contributors is `git shortlog -sn --no-merges`.

## 19. Evolving this document

- Keep it agent-first: dense, scannable, honest about gaps.
- When bolty gains a capability, update §11 and add a usage snippet in §3 if there is a new ergonomic.
- When a sharp edge is fixed, move it out of §15 rather than deleting silently — commit history is the only other record.
- If the document exceeds ~500 lines, split into topic files and keep this one as an index.
