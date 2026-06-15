<!--
SPDX-FileCopyrightText: 2024 bolty contributors
SPDX-License-Identifier: Apache-2.0
-->

# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

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

