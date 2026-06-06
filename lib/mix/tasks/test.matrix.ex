# SPDX-FileCopyrightText: 2024 bolty contributors
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

  `BOLT_TCP_PORT` is respected (defaults to 7687).
  """

  @requirements ["compile"]

  @impl Mix.Task
  def run(args) do
    versions = Bolty.BoltProtocol.Versions.available_versions()
    port = System.get_env("BOLT_TCP_PORT", "7687")

    per_version_results =
      Enum.map(versions, fn version ->
        version_str = Float.to_string(version)
        Mix.shell().info([:bright, "\n── Bolt #{version_str} ──\n"])

        {_, status} =
          System.cmd(
            "mix",
            ["test" | args],
            env: [{"BOLT_VERSIONS", version_str}, {"BOLT_TCP_PORT", port}],
            into: IO.stream(:stdio, :line)
          )

        {version_str, status}
      end)

    # Test both ranges negotiated together: server picks the best version from
    # the full latest_versions() handshake (two-range offer).
    Mix.shell().info([:bright, "\n── Both ranges (full negotiation) ──\n"])

    {_, negotiation_status} =
      System.cmd(
        "mix",
        ["test", "--only", "core" | args],
        env: [{"BOLT_TCP_PORT", port}],
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
end
