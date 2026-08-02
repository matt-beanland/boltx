# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.Policy.Resolver do
  @moduledoc false

  alias Bolty.Policy

  # Named Cypher features and the first calendar release (yyyymm) that speaks
  # them. Cypher gains features every release as it converges on GQL, so this is
  # the extension point: naming one is a row here plus a `@typedoc` entry on
  # `Bolty.Policy.cypher_feature/0` and a docs row — never a new struct field.
  #
  # Boundaries here are probed against real servers, not read off release notes:
  # each was confirmed as a SyntaxError on the previous release and accepted on
  # the one recorded.
  @cypher_features [
    {:disjoint_by, 202_606},
    {:vector_search_in_predicate, 202_606},
    {:vector_hfq, 202_606}
  ]

  @doc """
  Resolve a `%Bolty.Policy{}` from the negotiated Bolt version and optional
  HELLO response metadata.

  Pure function — no I/O, no process calls, no globals. Safe to call in tests
  against synthetic inputs.

  When called before HELLO (to build a preliminary policy for crafting the
  HELLO message itself), pass `%{}` for `server_metadata`. The wire-level
  dimensions depend only on `bolt_version`, so they are identical in the
  preliminary and final policies. The Cypher capability flags (`cypher_5`,
  `cypher_25`, `dynamic_labels`, `cypher_features`) are derived from the HELLO
  `server` string and are only populated in the final policy — they default to
  `false`/empty until then.

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
    |> put_cypher_features(bolt_version, server_version)
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

  # Bolt 5.7 switched to GQL-compliant FAILURE responses: neo4j_code/description
  # instead of code/message.
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
    case calendar_release(server_version) do
      nil -> %{policy | cypher_25: false}
      release -> %{policy | cypher_25: release >= 202_506}
    end
  end

  # Dynamic labels/types landed in Cypher 5.26 and every calendar release after,
  # under plain CYPHER 5 (a strict superset of cypher_25). server_version is e.g.
  # "Neo4j/5.26.27" or "Neo4j/2025.06.0".
  defp put_dynamic_labels(policy, _bolt_version, server_version) do
    dynamic? =
      case server_version do
        "Neo4j/5.26." <> _ -> true
        version when is_binary(version) -> calendar_release(version) != nil
        _ -> false
      end

    %{policy | dynamic_labels: dynamic?}
  end

  # Named Cypher 25 features the server's release is new enough to speak. A
  # 5.26.x LTS (no calendar release, no Cypher 25) resolves to the empty set, as
  # does a server whose agent string bolty can't place — an unknown server is
  # assumed to have nothing beyond the baseline rather than the reverse.
  defp put_cypher_features(policy, _bolt_version, server_version) do
    features =
      case calendar_release(server_version) do
        nil ->
          MapSet.new()

        release ->
          for {feature, since} <- @cypher_features, release >= since, into: MapSet.new() do
            feature
          end
      end

    %{policy | cypher_features: features}
  end

  # The server's calendar release as a comparable `yyyymm` integer, or nil for a
  # semver server ("Neo4j/5.26.28"), a non-Neo4j agent string, or no metadata.
  #
  # Deliberately not surfaced on the policy: capabilities are what consumers
  # should gate on, and a version string is precisely what a Bolt server
  # emulating Neo4j has reason to pin or misreport.
  defp calendar_release(server_version) when is_binary(server_version) do
    case Regex.run(~r/^Neo4j\/(\d{4})\.(\d{2})\./, server_version) do
      [_, year, month] -> String.to_integer(year) * 100 + String.to_integer(month)
      _ -> nil
    end
  end

  defp calendar_release(_server_version), do: nil
end
