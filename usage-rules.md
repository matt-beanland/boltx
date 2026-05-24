<!--
SPDX-FileCopyrightText: 2024 bolty contributors
SPDX-License-Identifier: Apache-2.0
-->

# AGENTS.md — bolty

> Status: v1 draft. Written primarily for agents that will **use** or **work on** bolty. Secondary audience: future maintainers (us) who need to remember why it is shaped the way it is. Expected to evolve.

## 1. What bolty is

`bolty` is an Elixir driver for [Neo4j](https://neo4j.com/) and other Bolt-speaking graph databases (notably Memgraph). It is a **reluctant fork** of [`boltx`](https://github.com/sagastume/boltx) — kept alive because specific fixes were needed (duration handling, maintenance), not because we wanted a new driver. Treat it as boltx-compatible in spirit; the upstream acknowledgment belongs to Luis Sagastume (`boltx`) and Florin Patrascu (`bolt_sips`).

- **Protocol**: Bolt 1.0 → 5.4, with version negotiation at handshake time.
- **Server compatibility**: Neo4j 3.0.x → 5.13, Memgraph 2.13 (Bolt 5.0–5.2, advertised as Neo4j/5.2.0).
- **Pooling/transactions/prepared queries** via [`DBConnection`](https://hexdocs.pm/db_connection).
- **Hex package**: `:bolty` (current version in `mix.exs`).

## 2. When to use bolty — and when not to

**Use bolty when**:
- You need direct Cypher/Bolt access from Elixir with `DBConnection` pooling.
- You are speaking to Neo4j or a Bolt-compatible engine (Memgraph).
- You want to hand-write Cypher and deal in `Bolty.Types.*` structs.

**Do not use bolty when**:
- You want Ash-style resources, actions, policies on top of Neo4j — use `ash_neo4j`, which sits on top of bolty.
- You need **streaming** of large result sets (not implemented; see Feature Support).
- You need **cluster routing** (not implemented; see Feature Support).

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
| `Bolty.transaction(conn, fun, opts \\ [], extra \\ %{})` | Transaction | `extra` is threaded into the BEGIN message (see §7). |
| `Bolty.rollback(conn, reason)` | Explicit rollback | Delegates to `DBConnection.rollback/2`. |
| `Bolty.Response.first/1` | Grab the first result row | Returns a map `%{field => value}` or `nil`. |

**`params`** is a map of Cypher parameters. Most Elixir values pass through unchanged; `Bolty.Types.Point` is formatted specially (see §6). If you want to pass `TimeWithTZOffset` / `DateTimeWithTZOffset` into Cypher, call `format_param/1` yourself — only `Point` is auto-formatted at the top level today.

**`opts`** accepts per-query extras lifted into the Bolt `extra` map: `:bookmarks`, `:mode` (`"r"` / `"w"`), `:db`, `:tx_metadata`. Everything else flows through to `DBConnection`.

## 5. Connection options

Canonical option names (what `Bolty.Client.Config.new/1` actually reads):

| Option | Meaning | Default |
| --- | --- | --- |
| `:uri` | `<scheme>://<host>[:<port>]` — wins over host/port/scheme | `nil` |
| `:hostname` | Host | `BOLT_HOST` env → `"localhost"` |
| `:port` | Port | `BOLT_TCP_PORT` env → `7687` |
| `:scheme` | One of the schemes below | `"bolt+s"` |
| `:auth` | `[username: ..., password: ...]` | required |
| `:versions` | Bolt versions to negotiate (e.g. `[4.4]` to prevent Bolt 5) | server-driven negotiation |
| `:user_agent` | Client identity string | `"bolty/<version>"` |
| `:notifications_minimum_severity` | Bolt 5.2+ | `nil` |
| `:notifications_disabled_categories` | Bolt 5.2+ | `nil` |
| `:connect_timeout` | ms | `15_000` |
| `:ssl_opts` | `:ssl.tls_client_option()` list | merged with scheme-implied defaults |
| `:socket_options` | `:gen_tcp.connect_option()` list | `[mode: :binary, packet: :raw, active: false]` |
| DBConnection opts (`:name`, `:pool_size`, `:max_overflow`, `:after_connect`, ...) | flow through | |

**Env-var precedence for auth is a sharp edge**: `BOLT_USER` and `BOLT_PWD` override the values you pass in `:auth`. Unset them explicitly if you don't want that.

### URI schemes / TLS

| URI scheme | TLS | ssl_opts merge |
| --- | --- | --- |
| `neo4j`, `bolt` | off | — |
| `neo4j+s`, `bolt+s` | on | `verify: :verify_none` (full cert, but no verification) |
| `neo4j+ssc`, `bolt+ssc` | on | `verify: :verify_peer` (self-signed allowed) |

Default scheme when nothing is specified is `bolt+s`.

## 6. Value mapping — Elixir ↔ Bolt/Neo4j

All in `Bolty.Types`:

- Graph: `Node`, `Relationship`, `UnboundRelationship`, `Path` (with `Path.graph/1` walking helper).
- Temporal (Bolt v2+): standard Elixir `Time`, `NaiveDateTime`, `Duration`; and `TimeWithTZOffset`, `DateTimeWithTZOffset` when you need integer-offset timezones. DateTime encoding is now policy-driven: the connection resolves a `%Bolty.Policy{datetime: :legacy | :evolved}` at HELLO and the packer emits the matching struct tag (0x46/0x66 legacy on Bolt ≤ 4.x, 0x49/0x69 evolved on Bolt 5.x) with the matching body semantics (legacy = local-wall-clock seconds; evolved = UTC-instant seconds). Unpacker handles both on decode. Resolved in 0.0.10 — issue [#10](https://github.com/diffo-dev/bolty/issues/10). `Duration` round-trip as a native Neo4j duration was broken in 0.0.7 and fixed through 0.0.8 (microseconds) and 0.0.9 (stored-as-string) — issues [#6](https://github.com/diffo-dev/bolty/issues/6) and [#8](https://github.com/diffo-dev/bolty/issues/8).
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
2. Jsonable → string — choose `Bolty.ResponseEncoder.Json.Jason` (default) or `Bolty.ResponseEncoder.Json.Poison`; both optional deps declared in `mix.exs`.

## 10. Errors

`%Bolty.Error{module, code, bolt, packstream}` — a `defexception`. Known code atoms:

| Bolt error | Atom |
| --- | --- |
| `Neo.ClientError.Security.Unauthorized` | `:unauthorized` |
| `Neo.ClientError.Request.Invalid` | `:request_invalid` |
| `Neo.ClientError.Statement.SemanticError` | `:semantic_error` |
| `Neo.ClientError.Statement.SyntaxError` | `:syntax_error` |

Everything else becomes `:unknown`, with the raw map still available in `error.bolt`. Expand `@error_map` in `lib/bolty/error.ex` when a new code becomes worth pattern-matching on.

## 11. Feature support matrix

| Capability | Status |
| --- | --- |
| Queries (RUN/PULL) | ✅ |
| Transactions (explicit + implicit) | ✅ |
| Pooling (DBConnection) | ✅ |
| Encoding/decoding of graph, temporal, spatial types | ✅ |
| TLS variants (full / self-signed / off) | ✅ |
| Notifications opt-out (Bolt 5.2+) | ✅ |
| Streaming result sets | ❌ |
| Cluster routing (`neo4j://` autodiscovery) | ❌ |
| Vector / vector search (indexes, similarity ops) | ❌ — under investigation, issue [#13](https://github.com/diffo-dev/bolty/issues/13) |

If an agent needs routing or streaming today, that is not bolty's job — surface the gap to Matt rather than working around it silently.

## 12. Running tests

Tests are version-tagged. Defaults run only `:core`; everything else is disabled unless you opt in with env vars and tags.

- Env vars: `BOLT_VERSIONS` (e.g. `"5.2"`), `BOLT_TCP_PORT` (e.g. `7690`), `BOLT_USER`, `BOLT_PWD`, `BOLT_HOST`.
- Tags: `:core`, `:bolt_version_X_Y` (e.g. `:bolt_version_5_2`), `:bolt_X_x` (e.g. `:bolt_5_x`), `:last_version`.

Local server matrix via `docker-compose.yml`:

| Service | Image | Ports (host:container) | Bolt versions |
| --- | --- | --- | --- |
| `neo4j-3.4.0` | `neo4j:3.4.0` | `7688:7687` | 1.0, 2.0 |
| `neo4j-4.4` | `neo4j:4.4.27-community` | `7689:7687` | 3.0, 4.0–4.4 |
| `neo4j-5.26.22` | `neo4j:5.26.22-community` | `7690:7687` | 5.0–5.4 |
| `memgraph-2.13.0` | `memgraph/memgraph:2.13.0` | `7691:7687` | 5.0–5.2 |

All use credentials `neo4j / boltyPassword`.

Test runner orchestrates this via `./scripts/test-runner.sh -c "mix test" -b "1.0,5.2" -d "neo4j,memgraph"`. Requires Docker, docker-compose, `jq`; `bats` for the script's own tests. See `scripts/README.md`.

## 13. Development loop

- Elixir `~> 1.14`. `.tool-versions` pins the expected runtime.
- `mix format` — `.formatter.exs` configured.
- `mix credo` — `.credo.exs` tuned; keep warnings at 0.
- `mix dialyzer` — PLT adds `:jason`, `:poison`, `:mix`; `.dialyzer_ignore.exs` holds accepted noise.
- `mix docs` — ex_doc; README.md is the main page.
- `mix test --cover` / `mix coveralls` — 70% threshold gate.
- `mix bench` (if present as an alias) — uses `benchee`, outputs via `benchee_html`; benchees live in `benchees/`.

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

- Bolt ≤ 2.0 → `INIT`.
- Bolt 3.0–5.0 → `HELLO`.
- Bolt ≥ 5.1 → `HELLO` then `LOGON` (auth split out of HELLO).

`handle_execute/4` always runs via `DBConnection.prepare_execute` — bolty does **not** use real prepared statements; `DBConnection.Query` is implemented as a no-op passthrough in `lib/bolty/query.ex`. `handle_prepare`, `handle_close`, `handle_declare`, `handle_fetch`, `handle_deallocate` are all trivial; `handle_status` is hardcoded to `:idle`. Revisit if true streaming lands.

Fork posture: drift from boltx is minimised on purpose. When applying fixes, prefer surgical patches over refactors so upstream back-ports remain feasible.

Compliance goals: bolty aims for [REUSE](https://reuse.software/) compliance (licence metadata on every file, including deps handling). Currently non-compliant — tracked in issue [#12](https://github.com/diffo-dev/bolty/issues/12). Keep this in mind when adding new source files.

### Policy-driven packstream

Version-aware encoding lives in `%Bolty.Policy{}` — an internal struct resolved once at HELLO completion from `(bolt_version, server_version)` via `Bolty.Policy.Resolver`, stashed on both `Bolty.Connection` and `Bolty.Client` state, and threaded through every `pack/2` call as a second argument. Codecs pattern-match on policy fields and never read a version number directly; that is the acceptance criterion for any future dimension.

Policy is **not** user-facing — it's the driver's own distillation of negotiated facts about how Bolt and the server have evolved. Dimensions today:

- `:datetime` — `:legacy` on Bolt ≤ 4.x (tags 0x46/0x66, body carries local-wall-clock seconds) or `:evolved` on Bolt ≥ 5.0 (tags 0x49/0x69, body carries UTC-instant seconds). Implemented in 0.0.10 to resolve issue [#10](https://github.com/diffo-dev/bolty/issues/10).

When vectors (issue [#13](https://github.com/diffo-dev/bolty/issues/13)) land, add a new dimension to `Bolty.Policy`, extend `Bolty.Policy.Resolver` with a pure `put_vectors/3` clause, and dispatch the relevant codec on it — do **not** bypass the boundary.

Authoritative design (including calibration history and non-goals): [`.agent-notes/policy-design.md`](./.agent-notes/policy-design.md).

## 15. Sharp edges / known quirks

- `@error_map` only covers four Neo bolt errors; everything else collapses to `:unknown`. Extend when you need finer-grained handling.
- `format_param/1` at the top level only rewrites `Point`. Temporal-with-offset structs pass through as-is; call their own `format_param/1` if you need Cypher-ready strings.
- Env-var-overrides-opts precedence for `:auth` (BOLT_USER / BOLT_PWD) — as noted in §5.

## 16. Issues (GitHub)

Snapshot from `.agent-notes/issues.json` — re-dump to refresh.

**Open**

| # | Title | Label | Summary |
| --- | --- | --- | --- |
| [#12](https://github.com/diffo-dev/bolty/issues/12) | reuse compliance | enhancement | Make bolty (and its deps handling) REUSE-compliant. |
| [#13](https://github.com/diffo-dev/bolty/issues/13) | vector | enhancement | Investigate Neo4j vector / vector-search support. DozerDB caps at Neo4j 5.26.3 so the useful envelope is bounded; may need negotiated Bolt-version behaviour. |
| [#16](https://github.com/diffo-dev/bolty/issues/16) | boltx-era inheritance cleanup | maintenance | Drop `patch_bolt` dead wiring from `Bolty.Connection`, modernise `config/test.exs` and `.iex.exs` against the current `Bolty.Client.Config.new/1` option names, rewrite `Bolty.Response`'s Spanish docstring in English. Active on branch `16-boltx-related-maintenance`. |
| &mdash; | memgraph datetime calibration | maintenance | Separate follow-up: run the Europe/Berlin round-trip test against the `memgraph-2.13.0` docker-compose service when a Memgraph instance is available, then either add it as a regression test (if the resolver's default already works) or add a `server_version =~ "Memgraph"` branch in `Bolty.Policy.Resolver.put_datetime/3`. Deferred — no blocker for 0.0.10. |

**Closed (for historical context)**

| # | Title | Resolved in | Notes |
| --- | --- | --- | --- |
| [#5](https://github.com/diffo-dev/bolty/issues/5) | hex publish | 0.0.7 | Initial fork from `boltx` and Hex publication under the `bolty` name to avoid namespace collisions. |
| [#6](https://github.com/diffo-dev/bolty/issues/6) | duration microseconds | 0.0.8 | Elixir `Duration` was being serialised to ISO8601 string rather than native Neo4j duration struct. |
| [#8](https://github.com/diffo-dev/bolty/issues/8) | duration stored as string | 0.0.9 | Further fix — `Duration` outside of a map/struct wrapper was still being stored as a string. |
| [#10](https://github.com/diffo-dev/bolty/issues/10) | dateTime param illegal | 0.0.10 | `%DateTime{}` was packed with the evolved 0x69 tag unconditionally and broke against Neo4j 5.x when `:versions` was constrained to Bolt 4.x. Fixed by policy-driven packstream: `%Bolty.Policy{datetime: :legacy \| :evolved}` resolved at HELLO, dispatched in the packer. See `.agent-notes/policy-design.md`. |

## 17. Licensing and REUSE

bolty is Apache License 2.0 and is [REUSE](https://reuse.software/)-compliant. The compliance scheme — decided together with the maintainers and documented here so future contributors don't need to re-derive it:

- **Licence**: Apache-2.0 throughout. bolty derives from `boltx` (Luis Sagastume) which derives from `bolt_sips` (Florin Patrascu), both Apache-2.0. Upstream attribution lives in `NOTICE`; per-file headers carry the collective `bolty contributors` claim on our own modifications. Relicensing away from Apache-2.0 is not on the table — we don't own the upstream code and the patent grant is load-bearing for a protocol driver.
- **Per-file header template** (hash-comment languages — Elixir, YAML, shell, etc.):
  ```
  # SPDX-FileCopyrightText: 2024 bolty contributors
  # SPDX-License-Identifier: Apache-2.0
  ```
  For Markdown use HTML-comment form so GitHub renders it as nothing:
  ```html
  <!--
  SPDX-FileCopyrightText: 2024 bolty contributors
  SPDX-License-Identifier: Apache-2.0
  -->
  ```
  For shell scripts, the shebang stays on line 1; the header goes on lines 2–3.
- **When adding a new file**: apply the appropriate header on creation. `reuse lint` runs in CI (see `.github/workflows/ci.yml` → `reuse` job) and will fail a PR that ships an unheadered file.
- **Files that can't take inline headers** (JSON, `mix.lock`, terse dotfiles) are declared in `REUSE.toml` at the repo root. Add a new entry rather than hacking the comment syntax.
- **`LICENSES/Apache-2.0.txt`** is the canonical SPDX licence text — don't modify it. The root `LICENSE` mirrors it for GitHub's project-metadata scraper.
- **`NOTICE`** is the attribution chain — extend it only if the project derives from a new upstream.

`bolty contributors` is a collective attribution label; the authoritative list of contributors is `git shortlog -sn --no-merges`.

## 18. Evolving this document

- Keep it agent-first: dense, scannable, honest about gaps.
- When bolty gains a capability, update §11 and add a usage snippet in §3 if there is a new ergonomic.
- When a sharp edge is fixed, move it out of §15 rather than deleting silently — commit history is the only other record.
- If the document exceeds ~500 lines, split into topic files and keep this one as an index.
