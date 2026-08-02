# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.ConnectionTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Bolty.Connection
  alias Bolty.BoltProtocol.Versions

  @opts Bolty.TestHelper.opts()
  @opts_without_auth Bolty.TestHelper.opts_without_auth()

  @tag core: true
  test "connect/1 - disconnect/1 successful" do
    assert {:ok,
            %Connection{
              client: client,
              server_version: server_version,
              connection_id: connection_id
            } = conn_data} =
             Connection.connect(@opts)

    assert is_bitstring(server_version)
    assert is_bitstring(connection_id)
    assert is_tuple(client.bolt_version)
    assert :ok = Connection.disconnect(:stop, conn_data)
  end

  @tag core: true
  test "connect/1 - not successful with incorrect credentials" do
    opts = @opts_without_auth ++ [auth: [username: "baduser", password: "badsecret"]]

    {:error, %Bolty.Error{code: :unauthorized}} =
      Connection.connect(opts)
  end

  @tag core: true
  test "checkout/1 successful" do
    {:ok,
     %Connection{client: client, server_version: server_version, connection_id: connection_id} =
       conn_data} =
      Connection.connect(@opts)

    assert is_bitstring(server_version)
    assert is_bitstring(connection_id)
    assert is_tuple(client.bolt_version)

    assert {:ok, %Connection{client: _} = conn_data} =
             Connection.checkout(conn_data)

    :ok = Connection.disconnect(:stop, conn_data)
  end

  @tag :core
  test "connect/1 fails when connection is not available" do
    opts = [
      hostname: "192.0.0.198",
      connect_timeout: 1,
      auth: [username: "baduser"]
    ]

    assert {:error, %Bolty.Error{code: :timeout}} = Connection.connect(opts)
  end

  @tag :bolt_version_5_0
  test "connect/1 successful with bolt version 5.0" do
    {:ok,
     %Connection{client: client, server_version: server_version, connection_id: connection_id} =
       conn_data} =
      Connection.connect(@opts)

    assert String.starts_with?(server_version, "Neo4j/")
    assert client.bolt_version == {5, 0}
    assert is_bitstring(connection_id)
    assert String.contains?(connection_id, "bolt-")

    :ok = Connection.disconnect(:stop, conn_data)
  end

  @tag :bolt_version_5_1
  test "connect/1 successful with bolt version 5.1" do
    {:ok,
     %Connection{client: client, server_version: server_version, connection_id: connection_id} =
       conn_data} =
      Connection.connect(@opts)

    assert String.starts_with?(server_version, "Neo4j/")
    assert client.bolt_version == {5, 1}
    assert is_bitstring(connection_id)
    assert String.contains?(connection_id, "bolt-")

    :ok = Connection.disconnect(:stop, conn_data)
  end

  @tag :bolt_version_5_2
  test "connect/1 successful with bolt version 5.2" do
    {:ok,
     %Connection{client: client, server_version: server_version, connection_id: connection_id} =
       conn_data} =
      Connection.connect(@opts)

    assert String.starts_with?(server_version, "Neo4j/")
    assert client.bolt_version == {5, 2}
    assert is_bitstring(connection_id)
    assert String.contains?(connection_id, "bolt-")

    :ok = Connection.disconnect(:stop, conn_data)
  end

  @tag :bolt_version_5_3
  test "connect/1 successful with bolt version 5.3" do
    {:ok,
     %Connection{client: client, server_version: server_version, connection_id: connection_id} =
       conn_data} =
      Connection.connect(@opts)

    assert String.starts_with?(server_version, "Neo4j/")
    assert client.bolt_version == {5, 3}
    assert is_bitstring(connection_id)
    assert String.contains?(connection_id, "bolt-")

    :ok = Connection.disconnect(:stop, conn_data)
  end

  @tag :bolt_version_5_4
  test "connect/1 successful with bolt version 5.4" do
    {:ok,
     %Connection{client: client, server_version: server_version, connection_id: connection_id} =
       conn_data} =
      Connection.connect(@opts)

    assert String.starts_with?(server_version, "Neo4j/")
    assert client.bolt_version == {5, 4}
    assert is_bitstring(connection_id)
    assert String.contains?(connection_id, "bolt-")

    :ok = Connection.disconnect(:stop, conn_data)
  end

  @tag :bolt_version_5_6
  test "connect/1 successful with bolt version 5.6" do
    {:ok,
     %Connection{client: client, server_version: server_version, connection_id: connection_id} =
       conn_data} =
      Connection.connect(@opts)

    assert String.starts_with?(server_version, "Neo4j/")
    assert client.bolt_version == {5, 6}
    assert is_bitstring(connection_id)
    assert String.contains?(connection_id, "bolt-")

    :ok = Connection.disconnect(:stop, conn_data)
  end

  @tag :bolt_version_5_7
  test "connect/1 successful with bolt version 5.7" do
    {:ok,
     %Connection{client: client, server_version: server_version, connection_id: connection_id} =
       conn_data} =
      Connection.connect(@opts)

    assert String.starts_with?(server_version, "Neo4j/")
    assert client.bolt_version == {5, 7}
    assert is_bitstring(connection_id)
    assert String.contains?(connection_id, "bolt-")

    :ok = Connection.disconnect(:stop, conn_data)
  end

  @tag :bolt_version_5_8
  test "connect/1 successful with bolt version 5.8" do
    {:ok,
     %Connection{client: client, server_version: server_version, connection_id: connection_id} =
       conn_data} =
      Connection.connect(@opts)

    assert String.starts_with?(server_version, "Neo4j/")
    assert client.bolt_version == {5, 8}
    assert is_bitstring(connection_id)
    assert String.contains?(connection_id, "bolt-")

    :ok = Connection.disconnect(:stop, conn_data)
  end

  @tag :last_version
  test "connect/1 successful with specific bolt version" do
    last_version = List.last(Versions.available_versions())
    opts = [versions: [last_version]] ++ @opts

    {:ok,
     %Connection{client: client, server_version: server_version, connection_id: connection_id} =
       conn_data} =
      Connection.connect(opts)

    assert String.starts_with?(server_version, "Neo4j/")
    assert client.bolt_version == last_version
    assert is_bitstring(connection_id)
    assert String.contains?(connection_id, "bolt-")

    :ok = Connection.disconnect(:stop, conn_data)
  end

  describe "Bolty.connection_info/1" do
    @tag :core
    test "returns negotiated metadata inside a transaction" do
      {:ok, pid} = Bolty.start_link(@opts)

      Bolty.transaction(pid, fn conn ->
        info = Bolty.connection_info(conn)

        assert is_binary(info.bolt_version)
        assert is_bitstring(info.server_version)
        assert %Bolty.Policy{} = info.policy
      end)
    end

    # Bolt 6.0 means a calendar-versioned server, which since 2026.06 carries
    # the named Cypher features. Asserts the inference against a real server
    # rather than a synthetic agent string (see Policy.ResolverTest for those).
    @tag :bolt_6_x
    test "cypher_features reflect the live server's calendar release" do
      {:ok, pid} = Bolty.start_link(@opts)
      %{server_version: server_version, policy: policy} = Bolty.connection_info(pid)

      if Regex.match?(~r/^Neo4j\/(20[3-9]\d|2026\.(0[6-9]|1[0-2]))/, server_version) do
        assert MapSet.member?(policy.cypher_features, :disjoint_by)
        assert MapSet.member?(policy.cypher_features, :vector_search_in_predicate)
        assert MapSet.member?(policy.cypher_features, :vector_hfq)
      else
        assert MapSet.equal?(policy.cypher_features, MapSet.new())
      end
    end

    @tag :core
    test "the :capabilities option overrides what the server version implies" do
      {:ok, pid} = Bolty.start_link([capabilities: [cypher_features: [:disjoint_by]]] ++ @opts)

      %{policy: policy} = Bolty.connection_info(pid)

      assert MapSet.equal?(policy.cypher_features, MapSet.new([:disjoint_by]))
    end

    @tag :core
    test "a non-overridable capability fails the connection cleanly" do
      Process.flag(:trap_exit, true)

      assert {:error, %Bolty.Error{code: :invalid_capability}} =
               Bolty.Connection.connect([pool_size: 1, capabilities: [vectors: true]] ++ @opts)
    end
  end

  # Issue #138: bolty read the GQLSTATUS `description` as the error message, so
  # every failure from a 5.7+ server arrived as boilerplate for its status class
  # and the diagnostic was discarded. A unit test with a captured map can't catch
  # a regression here — it needs a live server choosing which field to fill.
  describe "FAILURE diagnostics from a live server" do
    @tag :core
    test "an unknown procedure names the procedure" do
      {:ok, conn} = Bolty.start_link(@opts)

      assert {:error, %Bolty.Error{bolt: bolt}} = Bolty.query(conn, "CALL db.definitelyNotHere()")

      assert bolt.message =~ "db.definitelyNotHere",
             "expected the diagnostic naming the procedure, got: #{inspect(bolt.message)}"
    end

    @tag :core
    test "a syntax error locates itself, and GQL extras appear only on 5.7+" do
      {:ok, conn} = Bolty.start_link(@opts)
      %{policy: policy} = Bolty.connection_info(conn)

      assert {:error, %Bolty.Error{code: :syntax_error, bolt: bolt}} =
               Bolty.query(conn, "MATCH (n RETURN n")

      assert is_binary(bolt.message)

      if policy.gql_errors do
        assert bolt.gql_status =~ ~r/^\d{2}/

        # The diagnostic names the offending token and its position. `description`
        # is no substitute: 5.26 answers this very query with the 50N42 boilerplate
        # ("unexpected error ... See debug log for details"), which would report a
        # syntax error as an internal one.
        assert bolt.message =~ "RETURN"
        assert bolt.message != bolt.description

        # Optional even on 5.7+ — 5.26 omits it where 2026.x sends `_position`.
        case bolt do
          %{diagnostic_record: %{"_position" => position}} -> assert position["line"] == 1
          _ -> :ok
        end
      else
        refute Map.has_key?(bolt, :gql_status)
        refute Map.has_key?(bolt, :description)
      end
    end
  end

  describe "Connection.ping/1" do
    @tag :core
    test "with an active connection" do
      opts = [pool_size: 1] ++ @opts
      {:ok, conn_data} = Connection.connect(opts)

      assert {:ok, conn_data} == Connection.ping(conn_data)
    end

    @tag :core
    test "with an inactive connection" do
      opts = [pool_size: 1] ++ @opts
      {:ok, conn_data} = Connection.connect(opts)
      Connection.disconnect("ping test", conn_data)

      assert {:disconnect,
              %Bolty.Error{
                __exception__: true,
                bolt: nil,
                code: :db_ping_failed,
                module: Bolty.Connection,
                packstream: nil
              }, conn_data} == Connection.ping(conn_data)
    end
  end

  describe "Connection.handle_prepare/3" do
    @tag :core
    test "successful" do
      opts = [pool_size: 1] ++ @opts
      {:ok, conn_data} = Connection.connect(opts)
      assert {:ok, "", conn_data} == Connection.handle_prepare("", %{}, conn_data)
    end
  end

  describe "Connection.handle_close/3" do
    @tag :core
    test "successful" do
      opts = [pool_size: 1] ++ @opts
      {:ok, conn_data} = Connection.connect(opts)
      assert {:ok, "", conn_data} == Connection.handle_close("", %{}, conn_data)
    end
  end

  # handle_declare/4, handle_fetch/4 and handle_deallocate/4 are exercised
  # end-to-end against a live server in test/streaming_test.exs (they now run
  # RUN/PULL/DISCARD over a real cursor lifecycle rather than the old no-op
  # stubs, so an isolated unit assertion on their return shape isn't meaningful).

  describe "Connection.handle_status/2" do
    @tag :core
    test "successful" do
      opts = [pool_size: 1] ++ @opts
      {:ok, conn_data} = Connection.connect(opts)
      assert {:idle, conn_data} == Connection.handle_status(%{}, conn_data)
    end
  end
end
