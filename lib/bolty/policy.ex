# SPDX-FileCopyrightText: 2025 bolty contributors
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
  @typedoc """
  Named Cypher features the server understands, beyond what the coarse
  `cypher_5`/`cypher_25` language selectors imply.

  A curated set, not an exhaustive one: Cypher gains features every calendar
  release as it converges on GQL, and a boolean struct field per feature would
  neither scale nor be worth the permanent API surface. Membership is the check
  (`:disjoint_by in policy.cypher_features`), so naming a new feature is one
  atom here plus one row in the docs.

  Every member is a **Cypher 25** feature: it errors under a `CYPHER 5` prefix
  even on a server that lists it, so gate on `cypher_25` as well when emitting
  an explicit language selector.

    * `:disjoint_by` — `DISJOINT BY (expr, …) | AUTO | NONE` batch scheduling on
      `CALL { … } IN CONCURRENT TRANSACTIONS`, which prevents lock contention in
      parallel writes (Neo4j ≥ 2026.06).
    * `:vector_search_in_predicate` — `IN` predicates in vector search filters
      (`SEARCH n IN (VECTOR INDEX … WHERE n.prop IN […] LIMIT …)`), Neo4j ≥
      2026.06. Equality filters predate this; only the `IN` form is new, and on
      2026.05 it fails with an *internal* server error rather than cleanly, so
      gating matters.
    * `:vector_hfq` — Hi-Fidelity Quantized vector search: the
      `vector.quantization.type` and `vector.default_search_expansion_factor`
      index options on `CREATE VECTOR INDEX` (Neo4j ≥ 2026.06). A preview
      feature in 2026.06, expected GA in the next release — the availability
      boundary holds either way, but the option semantics may still move.
  """
  @type cypher_feature :: :disjoint_by | :vector_search_in_predicate | :vector_hfq

  @type t :: %__MODULE__{
          datetime: datetime(),
          notifications_field: notifications_field(),
          gql_errors: boolean(),
          vectors: boolean(),
          cypher_5: boolean(),
          cypher_25: boolean(),
          dynamic_labels: boolean(),
          cypher_features: MapSet.t(cypher_feature())
        }

  @typedoc """
  Policy fields a caller may assert by hand via the `:capabilities` connection
  option — the server-capability flags only.

  The wire-level dimensions (`datetime`, `notifications_field`, `gql_errors`,
  `vectors`) are negotiated facts about the Bolt connection, not opinions, and
  overriding one would just corrupt the wire; they are rejected.
  """
  @type overridable :: :cypher_5 | :cypher_25 | :dynamic_labels | :cypher_features

  @overridable [:cypher_5, :cypher_25, :dynamic_labels, :cypher_features]

  @doc """
  Applies caller-asserted capability overrides over a resolved policy.

  Bolty infers Cypher capabilities from the HELLO `server` string, which only
  works for a server that both *is* Neo4j and reports its real calendar
  release. A Bolt server that emulates Cypher 25 without following Neo4j's
  calendar — or that wears a pinned Neo4j agent string while implementing a
  different subset — cannot be inferred correctly in either direction, so the
  caller gets to state the truth instead:

      Bolty.start_link(capabilities: [cypher_25: true, cypher_features: [:disjoint_by]])

  Each given value **replaces** the inferred one rather than merging, so an
  override can withdraw a wrongly-inferred capability as well as add a missing
  one. Anything not named keeps its inferred value.

  Returns `{:error, %Bolty.Error{}}` for an unknown or non-overridable field, so
  a typo surfaces at connect rather than silently doing nothing.
  """
  @spec override(t(), keyword()) :: {:ok, t()} | {:error, Bolty.Error.t()}
  def override(%__MODULE__{} = policy, []), do: {:ok, policy}

  def override(%__MODULE__{} = policy, capabilities) when is_list(capabilities) do
    case Keyword.keys(capabilities) |> Enum.uniq() |> Enum.reject(&(&1 in @overridable)) do
      [] ->
        {:ok, Enum.reduce(capabilities, policy, &put_override/2)}

      invalid ->
        {:error,
         Bolty.Error.wrap(__MODULE__, %{
           code: :invalid_capability,
           message:
             "cannot override #{inspect(invalid)} — :capabilities accepts the server-capability " <>
               "flags #{inspect(@overridable)}; the wire-level dimensions are negotiated, not asserted"
         })}
    end
  end

  defp put_override({:cypher_features, features}, policy) when is_list(features),
    do: %{policy | cypher_features: MapSet.new(features)}

  defp put_override({key, value}, policy), do: %{policy | key => value}

  # defaults reflect the lowest supported Bolt version (5.0)
  defstruct datetime: :evolved,
            notifications_field: :notifications_disabled_categories,
            gql_errors: false,
            vectors: false,
            cypher_5: false,
            cypher_25: false,
            dynamic_labels: false,
            cypher_features: MapSet.new()
end
