<!--
SPDX-FileCopyrightText: 2024 bolty contributors
SPDX-License-Identifier: Apache-2.0
-->

# AGENTS.md

Notes for whoever picks this up next — human maintainer or coding agent, quite
possibly neither of the people who wrote these. The detailed reference is
[`usage-rules.md`](./usage-rules.md); this file is the orientation and the
hard-won bits that aren't obvious from the code.

## Working agreements

- **Conventional Commits**, always — they drive the changelog (see Releases). Types and sections are listed in `usage-rules.md` §16.
- **No "Co-Authored-By" trailers**, and **no AI/assistant attribution** anywhere in commits, PRs, or issues. Write them as a maintainer would.
- **Verify, don't assume.** If a request references an issue, read it (`gh issue view N`). If it leans on "how the other repos do it," check them (e.g. `gh api repos/diffo-dev/ash_neo4j/contents/...`) rather than guessing. When a decision changes committed infrastructure and intent is unclear, ask.

## Releases (git_ops)

bolty uses [`git_ops`](https://hex.pm/packages/git_ops) (configured in `config/dev.exs`), consistent with the other diffo-dev repos. Do **not** hand-edit the version or CHANGELOG.

Typical flow:

1. Feature branch → PR to `dev`. CI must be green.
2. Merge to `dev`.
3. `mix git_ops.release` on `dev` — bumps `@version` in `mix.exs`, updates the README dep snippet, writes the `CHANGELOG.md` section, commits and tags `vX.Y.Z`. `feat` → minor, `fix`/etc. → patch (pre-1.0 too).
4. Push `dev` and the tag; merge `dev` → `main`; `gh release create vX.Y.Z`; then **you** run `mix hex.publish` (needs Hex credentials).

Docs-only fix right after publishing? Within Hex's ~1-hour window you can correct the README, **move the tag** onto the fix, and re-publish the same version (`git tag -f`, `git push -f` the tag). Only `README.md` + `CHANGELOG.md` ship in the package (`mix.exs` `files`), so a fix to `usage-rules.md` / this file does not need a republish.

## CI

Runs on PRs to `dev`/`main` (it once targeted a non-existent `master` and silently never ran — keep an eye on the trigger). Gates: `mix format --check`, `mix compile --warnings-as-errors`, `mix dialyzer` (PLT cached under `priv/plts`), the Bolt-version test matrix (needs Neo4j), and REUSE. **Keep dialyzer at 0 warnings and the compile clean** — that baseline is the point of #50.

Every new source file needs an SPDX header (REUSE check), Apache-2.0.

## Local Neo4j — shared, handle with care

The test databases are **shared across diffo-dev repos** (bolty and ash_neo4j run the same containers). `docker-compose.yml` is aligned with ash_neo4j:

- `neo4j-bolt5` — `neo4j:5.26.27` on **7687** (Bolt 5.x)
- `neo4j-bolt6` — `neo4j:2026.05` on **7689** (Bolt 6.0)
- auth `neo4j` / `password`

Do **not** `docker rm` / `docker compose up --remove-orphans` against these — you may break another repo's session. Connect to what's already running. Note the suite's setup runs `MATCH (n) DETACH DELETE n`, so don't point it at a database you care about. Run the version matrix with `mix test.matrix` (`BOLT_6_TCP_PORT=7689` for the Bolt 6 server).

## Policy is the source of truth — and keep its docs in sync

Version- and server-driven behaviour lives in `%Bolty.Policy{}`, resolved once at HELLO by `Bolty.Policy.Resolver` and surfaced read-only via `Bolty.connection_info/1`. Codecs pattern-match policy fields; they never read a version number directly.

When you add or change a Policy flag you **must** update the docs in the same change — we shipped v0.2.0 with the flags but stale docs and had to chase it:

- README → "Negotiated capabilities" (the `connection_info/1` example **and** the capability/flag tables)
- `usage-rules.md` → §11 (feature matrix) and §14 (policy dimensions)

## Relationship to ash_neo4j

bolty is the Bolt driver beneath [ash_neo4j](https://github.com/diffo-dev/ash_neo4j) (the Ash data layer). Keep tooling and conventions aligned — `git_ops`, the docker-compose ports/creds, commit style. When unsure about a convention, look at what ash_neo4j does.
