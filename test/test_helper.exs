# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

alias Bolty.BoltProtocol.Versions

Logger.configure(level: :debug)

# Bolt versions are `{major, minor}` tuples internally; parse BOLT_VERSIONS
# ("5.4,6.0") into that form so the tags below line up with available_versions/0.
env_versions =
  System.get_env("BOLT_VERSIONS", "")
  |> String.split(",")
  |> Enum.reject(&(&1 == ""))
  |> Enum.map(fn v -> Versions.parse(v) |> elem(0) end)

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
    {major, minor} = version

    bolt_version_atom =
      String.to_atom("bolt_version_#{Integer.to_string(major)}_#{Integer.to_string(minor)}")

    bolt_version_x = String.to_atom("bolt_#{Integer.to_string(major)}_x")

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

defmodule Bolty.TestHelper do
  def opts() do
    [
      hostname: "127.0.0.1",
      auth: [username: "neo4j", password: "password"],
      user_agent: "boltyTest/1",
      ssl_opts: ssl_opts(),
      pool_size: 1,
      scheme: "bolt"
    ]
    |> with_env_overrides()
  end

  def opts_without_auth() do
    [
      hostname: "127.0.0.1",
      user_agent: "boltyTest/1",
      ssl_opts: ssl_opts(),
      pool_size: 1,
      scheme: "bolt"
    ]
    |> with_env_overrides()
  end

  # The driver no longer reads BOLT_VERSIONS / BOLT_TCP_PORT (removed in 0.3.0);
  # the test matrix (mix test.matrix / CI) still uses them to pick the Bolt
  # version and server port, so bridge them into explicit :versions / :port opts.
  #
  # NEO4J_HOST / NEO4J_SCHEME / NEO4J_PASSWORD additionally let the suite target a
  # non-local server — e.g. point it at a Neo4j Aura instance to validate the
  # driver against a real routed cluster over TLS:
  #
  #   NEO4J_HOST=xxxx.databases.neo4j.io NEO4J_SCHEME=neo4j+s \
  #     NEO4J_PASSWORD=... BOLT_TCP_PORT=7687 mix test
  defp with_env_overrides(opts) do
    opts
    |> maybe_put_env_port()
    |> maybe_put_env_versions()
    |> maybe_put_env_host()
    |> maybe_put_env_scheme()
    |> maybe_put_env_password()
  end

  defp maybe_put_env_host(opts) do
    case System.get_env("NEO4J_HOST", "") do
      "" -> opts
      host -> Keyword.put(opts, :hostname, host)
    end
  end

  defp maybe_put_env_scheme(opts) do
    case System.get_env("NEO4J_SCHEME", "") do
      "" -> opts
      scheme -> Keyword.put(opts, :scheme, scheme)
    end
  end

  defp maybe_put_env_password(opts) do
    case System.get_env("NEO4J_PASSWORD", "") do
      "" ->
        opts

      pw ->
        if Keyword.has_key?(opts, :auth),
          do: Keyword.update!(opts, :auth, &Keyword.put(&1, :password, pw)),
          else: opts
    end
  end

  defp maybe_put_env_port(opts) do
    case System.get_env("BOLT_TCP_PORT") do
      nil -> opts
      "" -> opts
      port -> Keyword.put(opts, :port, String.to_integer(port))
    end
  end

  defp maybe_put_env_versions(opts) do
    # Pass the raw string forms ("5.4") — the driver's :versions option now takes
    # strings; floats are deprecated and would log a warning on every run.
    case System.get_env("BOLT_VERSIONS", "") |> String.split(",") |> Enum.reject(&(&1 == "")) do
      [] -> opts
      versions -> Keyword.put(opts, :versions, versions)
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
