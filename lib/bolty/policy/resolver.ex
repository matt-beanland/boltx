# SPDX-FileCopyrightText: 2024 bolty contributors
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
  HELLO message itself), pass `%{}` for `server_metadata`. All current
  dimensions depend only on `bolt_version`, so the preliminary and final
  policies are identical in practice.

  `server_metadata` is the raw map returned by HELLO (keys are strings:
  `"server"`, `"hints"`, `"connection_id"`, etc.).
  """
  @spec resolve(float() | nil, map()) :: Policy.t()
  def resolve(bolt_version, server_metadata) when is_map(server_metadata) do
    server_version = Map.get(server_metadata, "server")

    %Policy{}
    |> put_datetime(bolt_version, server_version)
    |> put_notifications_field(bolt_version, server_version)
    |> put_gql_errors(bolt_version, server_version)

    # |> put_vectors(bolt_version, server_version)  # issue #13
  end

  # Bolt 5.x uses evolved DateTime struct tags (0x49/0x69).
  # Bolt 4.x and below (no longer supported) used :legacy.
  # Memgraph advertises "Neo4j/5.2.0" but speaks Bolt 5.x — :evolved applies.
  defp put_datetime(policy, bolt_version, _server_version)
       when is_float(bolt_version) and bolt_version >= 5.0 do
    %{policy | datetime: :evolved}
  end

  defp put_datetime(policy, _bolt_version, _server_version), do: policy

  # Bolt 5.6 renamed the HELLO field for disabled notification categories.
  defp put_notifications_field(policy, bolt_version, _server_version)
       when is_float(bolt_version) and bolt_version >= 5.6 do
    %{policy | notifications_field: :notifications_disabled_classifications}
  end

  defp put_notifications_field(policy, _bolt_version, _server_version), do: policy

  # Bolt 5.7 switched to GQL-compliant FAILURE responses: neo4j_code/description
  # instead of code/message.
  defp put_gql_errors(policy, bolt_version, _server_version)
       when is_float(bolt_version) and bolt_version >= 5.7 do
    %{policy | gql_errors: true}
  end

  defp put_gql_errors(policy, _bolt_version, _server_version), do: policy
end
