<!--
SPDX-FileCopyrightText: 2025 bolty contributors
SPDX-License-Identifier: Apache-2.0
-->

# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [v0.4.0](https://github.com/diffo-dev/bolty/compare/v0.3.0...v0.4.0) (2026-08-02)




### CI/CD:

* move the Bolt 6 server from Neo4j 2026.05 to 2026.06 by Matt Beanland

### Features:

* name Cypher features on the policy, and let callers assert them by Matt Beanland

### Bug Fixes:

* surface the server's diagnostic, not the GQLSTATUS boilerplate by Matt Beanland

* declare the Policy struct before override/2 expands it by Matt Beanland

### Testing:

* assert the shape of planner-version, not its digits by Matt Beanland

## [v0.3.0](https://github.com/diffo-dev/bolty/compare/v0.2.1...v0.3.0) (2026-07-07)
### Breaking Changes:

* migrate JSON encoding to native Elixir JSON; drop jason/poison (#125) by Matt Beanland



### Chores:

* correct copyright year 2024 -> 2025 by Matt Beanland

* fix inaccurate @specs and type-completeness nits (#111) by Matt Beanland

* remove unreachable Bolt <5.0 legacy datetime code (#104) by Matt Beanland

* swap tzdata for tz to drop the hackney dev/test tail (#99) by Matt Beanland

* drop obsolete build_embedded and no-op test alias (#78) by Matt Beanland

* API ergonomics cleanup + dead-dep removal (#79) by Matt Beanland

* add shared pre-push hook for fast lint checks by Matt Beanland

* group dependabot updates to reduce PR noise by Matt Beanland

* bump erlang/elixir to 29.0.2 and 1.20.2 by Matt Beanland

* bump dependencies by Matt Beanland

### CI/CD:

* run mix credo in the static-analysis job (#78) by Matt Beanland

* bump Neo4j 5.26 LTS to 5.26.28 in the test matrix by Matt Beanland

* run the TLS verification suite by Matt Beanland

### Documentation:

* note Erlang :ssl rejects self-signed server certs under +s by Matt Beanland

* point to Neo4j SSL framework docs for server cert setup by Matt Beanland

* add TLS connection examples to README and usage-rules by Matt Beanland

* note Duration microsecond precision limitation (#129) by Matt Beanland

* document result streaming (#59) by Matt Beanland

* correct inverted verify values in usage-rules TLS scheme table by Matt Beanland

* add cluster/SSR guide and update usage-rules (#113) by Matt Beanland

* document :routing, :mode and :bookmarks (#113) by Matt Beanland

* README note for the tz-database requirement; preserve the error code (#100) by Matt Beanland

* expand the Bolty landing moduledoc + doc query_many!/4 (#78) by Matt Beanland

* declare the public/internal API boundary (#77) by Matt Beanland

* package and doc-config quick wins by Matt Beanland

* refresh AGENTS.md Local Neo4j section for 5.26.28 + TLS by Matt Beanland

### Features:

* emit [:bolty, :stream, :start|:fetch|:stop] telemetry (#59) by Matt Beanland

* lazy result streaming via DBConnection cursor callbacks (#59) by Matt Beanland

* send HELLO routing field to enable server-side routing (#113) by Matt Beanland

* validate start_link/1 options against an allowlist (#121) by Matt Beanland

* @spec the public API surface (#77) by Matt Beanland

* spec the internal version surface for dialyzer (#77) by Matt Beanland

* syntax-aware statement splitter for query_many by Matt Beanland

* represent Bolt versions as strings/tuples, not floats by Matt Beanland

* add per-query recv timeouts for post-connect reads by Matt Beanland

* emit :telemetry events for query and connect lifecycle by Matt Beanland

### Bug Fixes:

* render Duration JSON to match Neo4j toString; fix negative/zero (#129) by Matt Beanland

* suppress hex debug log for messages carrying credentials (#123) by Matt Beanland

* redact auth credentials from debug log (#109) by Matt Beanland

* remove dead :ssl option and warn on its use (#107) by Matt Beanland

* close remaining error-surface raise-through gaps (#110) by Matt Beanland

* re-coalesce surviving range minors instead of flattening them by Matt Beanland

* classify range :versions entries minor-by-minor, not as one unit by Matt Beanland

* reject :versions bolty doesn't implement at config time by Matt Beanland

* wrap handshake failures as %Bolty.Error{} instead of crashing (#106) by Matt Beanland

* clear error (not a crash) when a named-zone datetime has no tz database (#100) by Matt Beanland

* type Query/Queries `extra` as the map it actually is (#77) by Matt Beanland

* convert remaining float version comparisons to tuples by Matt Beanland

* reject unknown PackStream markers instead of silently misdecoding by Matt Beanland

* deterministic PackStream map key ordering by Matt Beanland

* raise Elixir floor to ~> 1.17 and CI-test it by Matt Beanland

* uniform config precedence and remove env-var config by Matt Beanland

* unify the error surface to always return %Bolty.Error{} by Matt Beanland

* correct inverted TLS verification and stop overriding user ssl_opts by Matt Beanland

### Refactoring:

* flatten log_client_message_hex nesting to satisfy credo by Matt Beanland

* deduplicate Bolt message boilerplate (#78) by Matt Beanland

* clear credo refactoring findings (#78) by Matt Beanland

### Style:

* satisfy mix format in client_test.exs by Matt Beanland

### Testing:

* allow targeting a non-local server via NEO4J_HOST/SCHEME/PASSWORD by Matt Beanland

* cover result streaming end-to-end (#59) by Matt Beanland

* un-hide TLS/config unit tests from bare mix test (#108) by Matt Beanland

* make bolty_test serial to stop async DB-truncate flake by Matt Beanland

* split unit/integration suites and add PackStream property tests by Matt Beanland

* add TLS integration rig on neo4j 5.26.28 by Matt Beanland

## [v0.2.1](https://github.com/diffo-dev/bolty/compare/v0.2.0...v0.2.1) (2026-06-26)




### Chores:

* remove dead Bolty.Client.checkin/1 (#54) by Matt Beanland

### CI/CD:

* cover Bolt 6.0 (2026.05) and Bolt 5.x fallback (#65) by Matt Beanland

### Documentation:

* scope dynamic_labels to pattern position only (#53) by Matt Beanland

### Bug Fixes:

* return bound Relationship structs from Path.graph/1 (#55) by Matt Beanland

* disconnect with the original error if a recovery RESET raises (#58) by Matt Beanland

* reassemble multi-chunk Bolt messages on the receive path (#57) by Matt Beanland

* classify common Neo4j status codes in Bolty.Error (#54) by Matt Beanland

* reset connection after any FAILURE to recover FAILED state (#54) by Matt Beanland

### Testing:

* stop the #54 constraint recovery test leaking its constraint by Matt Beanland

* stabilize the #54 happy-path commit test against async truncate by Matt Beanland

## [v0.2.0](https://github.com/diffo-dev/bolty/compare/v0.1.0...v0.2.0) (2026-06-15)




### Chores:

* align test DB compose with ash_neo4j and retire bats test-runner by Matt Beanland

* reference Neo4j 5.26.27 in compose, docs and fixtures by Matt Beanland

* replace git-cliff with git_ops for releases by Matt Beanland

### CI/CD:

* run on dev/main and add dialyzer + warnings-as-errors gate by Matt Beanland

### Features:

* policy: add cypher_5, cypher_25 and dynamic_labels flags by Matt Beanland

### Bug Fixes:

* ci: correct Neo4j test auth password and bump matrix image to 5.26.27 by Matt Beanland

* bolty: type transaction/4 extra_parameters as map by Matt Beanland

* error: preserve atom error codes in Error.wrap/2 by Matt Beanland

### Style:

* apply mix format to files with format drift by Matt Beanland

## v0.1.0 — 2026-06-06

### Bug Fixes
- Pin str_length in decode_string bitstring pattern ([`7a4fdff`](https://github.com/diffo-dev/bolty/commit/7a4fdff042ef7f3f345c6e19cbf262c061734401))

### Chores
- **BREAKING** Drop support for Neo4j 3.x and 4.x (Bolt 1.0–4.4) ([`1e2639b`](https://github.com/diffo-dev/bolty/commit/1e2639b72b728c5ec982b889e527ebe5c3b309f1))
- Remove dead legacy DateTime packer clauses ([`5245082`](https://github.com/diffo-dev/bolty/commit/52450821bf85f3da1966e41a3521975133f0b191))
- Remove stale :bolt_2_x/:bolt_3_x/:bolt_4_x test tags ([`48b69d9`](https://github.com/diffo-dev/bolty/commit/48b69d99255bbbb2078ee340fc27848adbc3b782))
- Remove dead Bolt ≤3/≤2 message clauses; document negotiated capabilities ([`12c540b`](https://github.com/diffo-dev/bolty/commit/12c540bd10a61a37d1ff4dc322e62677a59caae7))
- Add neo4j 2026.05 service; align passwords to 'password' ([`735570a`](https://github.com/diffo-dev/bolty/commit/735570a5ea011323a389e59f1025161b01346fb4))
- Drop Memgraph support (issue #15) ([`b546480`](https://github.com/diffo-dev/bolty/commit/b54648019b1d9f523d5c9a32bd927ff7c9187015))

### Documentation
- Update README for Bolt 6.0 and Neo4j 2026.05 support ([`18821ef`](https://github.com/diffo-dev/bolty/commit/18821efa97f446ad3565eed8618cee1d5296cbbc))

### Features
- Add mix test.matrix and mix changelog tasks; bump to 0.1.0 ([`aaa4df3`](https://github.com/diffo-dev/bolty/commit/aaa4df3b81fe0432e39be77e0d8cfc80a64ce5fb))
- Add support for Bolt 5.6, 5.7, and 5.8 (Neo4j 5.26.26 LTS) ([`d31d13a`](https://github.com/diffo-dev/bolty/commit/d31d13a189e9206d24830424e0eb447bd50941ca))
- Document :versions as first-class config; deprecate BOLT_VERSIONS ([`cad2b00`](https://github.com/diffo-dev/bolty/commit/cad2b00e8e5438a6dd2f13d47d69ba4628785cc3))
- Expose negotiated connection capabilities via Bolty.connection_info/1 ([`04daf05`](https://github.com/diffo-dev/bolty/commit/04daf058b4f33ba42284d1c86cdb7fa5b185d17c))
- Add Bolt 6.0 support (Neo4j 2026.05) ([`3429612`](https://github.com/diffo-dev/bolty/commit/3429612750e0ee125674dea12ce5455e0c4a8640))
- Route Bolt 6.x to separate port in test.matrix ([`526d842`](https://github.com/diffo-dev/bolty/commit/526d8420605a79f9990c931e37d3a3f2be834b24))
- Add Vector type pack/unpack for Bolt 6.0 (issue #13) ([`3f04e9c`](https://github.com/diffo-dev/bolty/commit/3f04e9c5abcf2dc8ced123755dfa7f36c99e8cc5))
- Add Bolt version guard and docs for Vector type ([`3f28f94`](https://github.com/diffo-dev/bolty/commit/3f28f94af9a58320d180a9171a2833bb6d92ad28))

### Refactoring
- Make Policy the source of truth for all Bolt version-driven behaviour ([`f5b1d08`](https://github.com/diffo-dev/bolty/commit/f5b1d08f8d9fb5498255bccaf8811f032b6b9003))

### Testing
- Update message encoder tests from Bolt 3.x/2.x to 5.x ([`7afc3e8`](https://github.com/diffo-dev/bolty/commit/7afc3e836d1d66137251e115b3f0a3fdf78d79bc))
- Remove hardcoded server version assertions in connection_test ([`c5f27ac`](https://github.com/diffo-dev/bolty/commit/c5f27acf4ec4ca68c0e918d44a3f1307d7cc2b78))

## v0.0.13

* `%Bolty.Types.Point{}` parameters are now sent as native PackStream Points instead of being silently converted to Maps. This allows Points (and arrays of Points) to be stored directly as Neo4j node properties. **Breaking:** callers that pass a `%Bolty.Types.Point{}` to Cypher's `point()` constructor must now pass a Map instead (or use `Bolty.Types.Point.format_param/1` to convert). See https://github.com/diffo-dev/bolty/pull/35

**Full Changelog**: https://github.com/diffo-dev/bolty/compare/0.0.12...0.0.13

## v0.0.12

* Execute/4 sends send_reset for :syntax_error/:semantic_error when inside a transaction ([#26](https://github.com/diffo-dev/bolty/pull/26))
* Additional bolty issues with transactions ([#28](https://github.com/diffo-dev/bolty/pull/28))
* Unknown Error (CaseClauseError) no case clause matching: `{:ignored, [0, 0]}` ([#29](https://github.com/diffo-dev/bolty/pull/29))

**Full Changelog**: https://github.com/diffo-dev/bolty/compare/0.0.11...0.0.12

## v0.0.11

* Fix UndefinedFunctionError when formatting a Neo4j EntityNotFound error ([#21](https://github.com/diffo-dev/bolty/pull/21))

**Full Changelog**: https://github.com/diffo-dev/bolty/compare/0.0.10...0.0.11

## v0.0.10

* DateTime param illegal — policy-driven PackStream encoding ([#14](https://github.com/diffo-dev/bolty/pull/14))

**Full Changelog**: https://github.com/diffo-dev/bolty/compare/0.0.9...0.0.10

## v0.0.9

* Fix duration stored as string

## v0.0.8

* Fix duration microseconds

## v0.0.7

* Initial fork from boltx v0.0.6
* Duration support
* Maintenance
* Negotiate range

