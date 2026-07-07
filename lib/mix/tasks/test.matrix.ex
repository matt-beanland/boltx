# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Mix.Tasks.Test.Matrix do
  use Mix.Task

  @shortdoc "Runs the test suite against every supported Bolt version"

  @moduledoc """
  Runs `mix test` once per supported Bolt version and prints a pass/fail
  summary. All versions are attempted even if one fails; exits non-zero if
  any version failed.

      mix test.matrix

  Extra flags are forwarded to each `mix test` invocation:

      mix test.matrix --only core

  Environment variables:
  - `BOLT_TCP_PORT` — port for Bolt 5.x servers (defaults to 7687)
  - `BOLT_6_TCP_PORT` — port for Bolt 6.x servers (defaults to `BOLT_TCP_PORT`)

  Example with the docker-compose services (Bolt 5.x on 7687, Bolt 6.x on 7689):

      BOLT_6_TCP_PORT=7689 mix test.matrix
  """

  @requirements ["compile"]

  @impl Mix.Task
  def run(args) do
    versions = Bolty.BoltProtocol.Versions.available_versions()
    default_port = System.get_env("BOLT_TCP_PORT", "7687")
    bolt6_port = System.get_env("BOLT_6_TCP_PORT", default_port)

    per_version_results =
      Enum.map(versions, fn version ->
        {version_str, port} = version_env(version, default_port, bolt6_port)
        Mix.shell().info([:bright, "\n── Bolt #{version_str} (port #{port}) ──\n"])

        {_, status} =
          System.cmd(
            "mix",
            ["test" | args],
            env: [{"BOLT_VERSIONS", version_str}, {"BOLT_TCP_PORT", port}],
            into: IO.stream(:stdio, :line)
          )

        {version_str, status}
      end)

    # Test full negotiation: server picks the best version it supports from the
    # complete latest_versions() handshake offer. Run against the Bolt 6 port
    # so the result reflects the highest available version.
    Mix.shell().info([:bright, "\n── Full negotiation (port #{bolt6_port}) ──\n"])

    {_, negotiation_status} =
      System.cmd(
        "mix",
        ["test", "--only", "core" | args],
        env: [{"BOLT_TCP_PORT", bolt6_port}],
        into: IO.stream(:stdio, :line)
      )

    results = per_version_results ++ [{"both-range negotiation", negotiation_status}]

    Mix.shell().info([:bright, "\n── Matrix results ──\n"])

    for {label, status} <- results do
      tag = if status == 0, do: [:green, "PASS"], else: [:red, "FAIL"]
      Mix.shell().info(["  Bolt ", label, "  ", tag])
    end

    failures =
      results
      |> Enum.filter(fn {_, status} -> status != 0 end)
      |> Enum.map_join(", ", fn {v, _} -> v end)

    if failures != "" do
      Mix.raise("Bolt version(s) failed: #{failures}")
    end
  end

  @doc """
  Maps a `{major, minor}` version to the `{version_string, port}` a per-version
  `mix test` run should use: the string form for `BOLT_VERSIONS`, and the Bolt 6
  port for `major >= 6`, otherwise the default port. Pure — split out from the
  `System.cmd` loop so it can be unit-tested.
  """
  @spec version_env(
          {non_neg_integer(), non_neg_integer()},
          String.t(),
          String.t()
        ) :: {String.t(), String.t()}
  def version_env({major, _minor} = version, default_port, bolt6_port) do
    port = if major >= 6, do: bolt6_port, else: default_port
    {Bolty.BoltProtocol.Versions.format(version), port}
  end
end
