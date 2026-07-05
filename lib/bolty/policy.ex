# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.Policy do
  @moduledoc """
  Resolved driver behaviour for a single connection.

  Resolved from the negotiated Bolt version (and optionally the HELLO response
  metadata) at connection time, then stashed on the connection state and threaded
  into every pack/unpack/message call. Code pattern-matches on policy fields and
  never reads a Bolt or server version directly.

  Policy is an internal distillation of negotiated facts, not a user-facing
  configuration surface. Users influence policy by passing connection options
  (e.g. constraining `:versions` at negotiation).
  """

  @typedoc """
  DateTime encoding dialect. Bolty only ever negotiates Bolt 5.0+, which always
  uses the evolved struct tags (0x49/0x69) — `:evolved` is the only value.
  """
  @type datetime :: :evolved

  @typedoc """
  HELLO wire field name for disabled notification categories/classifications.

    * `:notifications_disabled_categories` — Bolt ≤ 5.5
    * `:notifications_disabled_classifications` — Bolt 5.6+ (spec rename)
  """
  @type notifications_field ::
          :notifications_disabled_categories | :notifications_disabled_classifications

  # Server-side Cypher language capabilities. Unlike the wire-level dimensions
  # above, these are derived from the HELLO `server` string (e.g.
  # "Neo4j/5.26.27", "Neo4j/2025.06.0") rather than the negotiated Bolt version,
  # so they are only meaningful in the *final* policy resolved after HELLO.
  #
  #   * cypher_5 — server speaks the `CYPHER 5` language (Neo4j >= 5.0). True for
  #     every currently supported server; lets consumers prefix `CYPHER 5`
  #     explicitly now that newer servers default to Cypher 25.
  #   * cypher_25 — server supports the `CYPHER 25` language selector
  #     (Neo4j >= 2025.06).
  #   * dynamic_labels — server supports dynamic node labels/types in *pattern
  #     position* (`MATCH (n:$(expr))`, `CREATE`/`MERGE`, dynamic relationship
  #     types). A Cypher 5 feature that landed in 5.26 and every calendar release
  #     after; it runs under plain `CYPHER 5`, so the set of servers with
  #     dynamic_labels is a strict superset of those with cypher_25 (a 5.26.x
  #     server has dynamic_labels: true but cypher_25: false).
  #
  #     This flag covers the pattern-position form ONLY. The `WHERE n:$(expr)`
  #     label *predicate* form is a separate Cypher 25 language feature — gate it
  #     on cypher_25, not dynamic_labels. It errors under `CYPHER 5` even on a
  #     server that supports Cypher 25, and is unsupported on 5.26.x.
  @type t :: %__MODULE__{
          datetime: datetime(),
          notifications_field: notifications_field(),
          gql_errors: boolean(),
          vectors: boolean(),
          cypher_5: boolean(),
          cypher_25: boolean(),
          dynamic_labels: boolean()
        }

  # defaults reflect the lowest supported Bolt version (5.0)
  defstruct datetime: :evolved,
            notifications_field: :notifications_disabled_categories,
            gql_errors: false,
            vectors: false,
            cypher_5: false,
            cypher_25: false,
            dynamic_labels: false
end
