# SPDX-FileCopyrightText: 2024 bolty contributors
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

  describe "Connection.handle_deallocate/4" do
    @tag :core
    test "successful" do
      opts = [pool_size: 1] ++ @opts
      {:ok, conn_data} = Connection.connect(opts)
      assert {:ok, "", conn_data} == Connection.handle_deallocate("", "", %{}, conn_data)
    end
  end

  describe "Connection.handle_declare/3" do
    @tag :core
    test "successful" do
      opts = [pool_size: 1] ++ @opts
      {:ok, conn_data} = Connection.connect(opts)
      assert {:ok, "", conn_data, nil} == Connection.handle_declare("", "", %{}, conn_data)
    end
  end

  describe "Connection.handle_fetch/3" do
    @tag :core
    test "successful" do
      opts = [pool_size: 1] ++ @opts
      {:ok, conn_data} = Connection.connect(opts)
      assert {:cont, "", conn_data} == Connection.handle_fetch("", "", %{}, conn_data)
    end
  end

  describe "Connection.handle_status/2" do
    @tag :core
    test "successful" do
      opts = [pool_size: 1] ++ @opts
      {:ok, conn_data} = Connection.connect(opts)
      assert {:idle, conn_data} == Connection.handle_status(%{}, conn_data)
    end
  end
end
