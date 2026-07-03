# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

alias Bolty.Utils.Converters

Logger.configure(level: :debug)

env_versions =
  System.get_env("BOLT_VERSIONS", "")
  |> String.split(",")
  |> Enum.reject(&(&1 == ""))
  |> Enum.map(&Converters.to_float/1)

# Is a Neo4j server configured for this run? CI, `mix test.matrix`, and local
# `BOLT_TCP_PORT=7687 mix test` all set one of these. When none is set (a plain
# `mix test` on a machine with no database), we exclude `:integration` so the
# DB-dependent suite is skipped and the unit tests run on their own — a
# contributor without Docker/Neo4j can still run `mix test`.
db_configured? =
  System.get_env("BOLT_TCP_PORT", "") != "" or env_versions != []

exclude = [
  :skip,
  :bench,
  :apoc,
  :legacy,
  # TLS integration tests need the TLS-enabled neo4j-bolt5 service (port 7687)
  # and generated certs; run explicitly with `mix test --include tls`.
  :tls
]

# With a DB present we run integration tests (subject to the version tags below),
# so `:core` is re-included to override version excludes for version-agnostic
# tests. With no DB, exclude `:integration` and don't re-include `:core` — the
# DB tests (all tagged `:integration`) drop out while unit tests still run.
{exclude, include} =
  if db_configured? do
    {exclude, [:core]}
  else
    {[:integration | exclude], []}
  end

available_versions = Bolty.BoltProtocol.Versions.available_versions()

{include, exclude} =
  Enum.reduce(available_versions, {include, exclude}, fn version, {inc, exc} ->
    [major | [minor]] =
      version |> Float.to_string() |> String.split(".") |> Enum.map(&String.to_integer/1)

    bolt_version_atom =
      String.to_atom("bolt_version_#{Integer.to_string(major)}_#{Integer.to_string(minor)}")

    bolt_version_x = String.to_atom("bolt_#{Integer.to_string(trunc(version))}_x")

    if version in env_versions do
      case version === List.last(available_versions) do
        true -> {[:last_version, bolt_version_x, bolt_version_atom | inc], exc}
        false -> {[bolt_version_x, bolt_version_atom | inc], exc}
      end
    else
      case version !== List.last(available_versions) do
        true -> {inc, [:last_version, bolt_version_x, bolt_version_atom | exc]}
        false -> {inc, [bolt_version_x, bolt_version_atom | exc]}
      end
    end
  end)

ExUnit.start(capture_log: true, assert_receive_timeout: 500, exclude: exclude, include: include)
Application.ensure_started(:porcelain)

defmodule Bolty.TestHelper do
  def opts() do
    [
      hostname: "127.0.0.1",
      auth: [username: "neo4j", password: "password"],
      user_agent: "boltyTest/1",
      ssl_opts: ssl_opts(),
      pool_size: 1,
      prefix: :default,
      scheme: "bolt",
      ssl: false
    ]
    |> with_env_overrides()
  end

  def opts_without_auth() do
    [
      hostname: "127.0.0.1",
      user_agent: "boltyTest/1",
      ssl_opts: ssl_opts(),
      pool_size: 1,
      max_overflow: 3,
      prefix: :default,
      scheme: "bolt",
      ssl: false
    ]
    |> with_env_overrides()
  end

  # The driver no longer reads BOLT_VERSIONS / BOLT_TCP_PORT (removed in 0.3.0);
  # the test matrix (mix test.matrix / CI) still uses them to pick the Bolt
  # version and server port, so bridge them into explicit :versions / :port opts.
  defp with_env_overrides(opts) do
    opts
    |> maybe_put_env_port()
    |> maybe_put_env_versions()
  end

  defp maybe_put_env_port(opts) do
    case System.get_env("BOLT_TCP_PORT") do
      nil -> opts
      "" -> opts
      port -> Keyword.put(opts, :port, String.to_integer(port))
    end
  end

  defp maybe_put_env_versions(opts) do
    case System.get_env("BOLT_VERSIONS", "") |> String.split(",") |> Enum.reject(&(&1 == "")) do
      [] -> opts
      versions -> Keyword.put(opts, :versions, Enum.map(versions, &Converters.to_float/1))
    end
  end

  defp ssl_opts() do
    [versions: [:"tlsv1.2"]]
  end

  @doc """
   Read an entire file into a string.
   Return a tuple of success and data.
  """
  def read_whole_file(path) do
    case File.read(path) do
      {:ok, file} -> file
      {:error, reason} -> {:error, "Could not open #{path} #{file_error_description(reason)}"}
    end
  end

  @doc """
    Open a file stream, and join the lines into a string.
  """
  def stream_file_join(filename) do
    stream = File.stream!(filename)
    Enum.join(stream)
  end

  defp file_error_description(:enoent), do: "because the file does not exist."
  defp file_error_description(reason), do: "due to #{reason}."
end

# Bolty.start_link(Application.get_env(:bolty, Bolt))

# I am using the test db for debugging and the line below will clear *everything*
# Bolty.query(Bolty.conn, "MATCH (n) OPTIONAL MATCH (n)-[r]-() DELETE n,r")
#
# todo: The tests should cleanup the data they create.

Process.flag(:trap_exit, true)
