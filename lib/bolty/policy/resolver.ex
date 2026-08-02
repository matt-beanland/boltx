# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.Policy.Resolver do
  @moduledoc false

  alias Bolty.Policy

  @doc """
  Resolve a `%Bolty.Policy{}` from the negotiated Bolt version and optional
  HELLO response metadata.

  Pure function — no I/O, no process calls, no globals. Safe to call in tests
  against synthetic inputs.

  When called before HELLO (to build a preliminary policy for crafting the
  HELLO message itself), pass `%{}` for `server_metadata`. The wire-level
  dimensions depend only on `bolt_version`, so they are identical in the
  preliminary and final policies. The Cypher capability flags (`cypher_5`,
  `cypher_25`, `dynamic_labels`) are derived from the HELLO `server` string and
  are only populated in the final policy — they default to `false` until then.

  `server_metadata` is the raw map returned by HELLO (keys are strings:
  `"server"`, `"hints"`, `"connection_id"`, etc.).
  """
  @spec resolve({non_neg_integer(), non_neg_integer()} | nil, map()) :: Policy.t()
  def resolve(bolt_version, server_metadata) when is_map(server_metadata) do
    server_version = Map.get(server_metadata, "server")

    %Policy{}
    |> put_datetime(bolt_version, server_version)
    |> put_notifications_field(bolt_version, server_version)
    |> put_gql_errors(bolt_version, server_version)
    |> put_vectors(bolt_version, server_version)
    |> put_cypher_5(bolt_version, server_version)
    |> put_cypher_25(bolt_version, server_version)
    |> put_dynamic_labels(bolt_version, server_version)
  end

  # Bolt 5.x uses evolved DateTime struct tags (0x49/0x69).
  # Bolt 4.x and below (no longer supported) used :legacy.
  defp put_datetime(policy, bolt_version, _server_version)
       when is_tuple(bolt_version) and bolt_version >= {5, 0} do
    %{policy | datetime: :evolved}
  end

  defp put_datetime(policy, _bolt_version, _server_version), do: policy

  # Bolt 5.6 renamed the HELLO field for disabled notification categories.
  defp put_notifications_field(policy, bolt_version, _server_version)
       when is_tuple(bolt_version) and bolt_version >= {5, 6} do
    %{policy | notifications_field: :notifications_disabled_classifications}
  end

  defp put_notifications_field(policy, _bolt_version, _server_version), do: policy

  # Bolt 5.7 switched to GQL-compliant FAILURE responses: `code` renamed to
  # `neo4j_code`, and gql_status/description/diagnostic_record/cause added
  # alongside the message (which stays the diagnostic in both eras — #138).
  defp put_gql_errors(policy, bolt_version, _server_version)
       when is_tuple(bolt_version) and bolt_version >= {5, 7} do
    %{policy | gql_errors: true}
  end

  defp put_gql_errors(policy, _bolt_version, _server_version), do: policy

  # Bolt 6.0 introduced the Vector PackStream struct (signature 0x56).
  defp put_vectors(policy, bolt_version, _server_version)
       when is_tuple(bolt_version) and bolt_version >= {6, 0} do
    %{policy | vectors: true}
  end

  defp put_vectors(policy, _bolt_version, _server_version), do: policy

  # Cypher 5 shipped with Neo4j 5.0 (Bolt 5.0). Every server bolty supports
  # speaks it, so the flag tracks the negotiated Bolt version. It lets consumers
  # opt into an explicit `CYPHER 5` prefix now that 2026.02+ servers default the
  # query language to Cypher 25.
  defp put_cypher_5(policy, bolt_version, _server_version)
       when is_tuple(bolt_version) and bolt_version >= {5, 0} do
    %{policy | cypher_5: true}
  end

  defp put_cypher_5(policy, _bolt_version, _server_version), do: policy

  # CYPHER 25 language selector arrived with Neo4j 2025.06 (a calendar-versioned
  # 5.x server). server_version is e.g. "Neo4j/2025.06.0" or "Neo4j/5.26.27".
  defp put_cypher_25(policy, _bolt_version, server_version) do
    cypher_25? =
      case server_version && Regex.run(~r/^Neo4j\/(\d{4})\.(\d{2})\./, server_version) do
        [_, year, month] ->
          String.to_integer(year) * 100 + String.to_integer(month) >= 202_506

        _ ->
          false
      end

    %{policy | cypher_25: cypher_25?}
  end

  # Dynamic labels/types landed in Cypher 5.26 and every calendar release after,
  # under plain CYPHER 5 (a strict superset of cypher_25). server_version is e.g.
  # "Neo4j/5.26.27" or "Neo4j/2025.06.0".
  defp put_dynamic_labels(policy, _bolt_version, server_version) do
    dynamic? =
      case server_version do
        "Neo4j/5.26." <> _ -> true
        version when is_binary(version) -> Regex.match?(~r/^Neo4j\/\d{4}\.\d{2}\./, version)
        _ -> false
      end

    %{policy | dynamic_labels: dynamic?}
  end
end
