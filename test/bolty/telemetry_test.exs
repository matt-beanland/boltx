# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.TelemetryTest do
  @moduledoc """
  Verifies the `[:bolty, :query]` span and the `[:bolty, :connect | :disconnect]`
  lifecycle events. Needs a live Neo4j (like the rest of the suite).
  """
  use ExUnit.Case, async: false

  alias Bolty.Connection

  @opts Bolty.TestHelper.opts()

  # Attach the listed events to a handler that forwards them to the test process,
  # and detach on exit. Returns the handler id.
  defp attach(events) do
    id = "bolty-telemetry-test-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach_many(
        id,
        events,
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(id) end)
    id
  end

  describe "query span" do
    setup do
      {:ok, conn} = Bolty.start_link([pool_size: 1] ++ @opts)
      %{conn: conn}
    end

    @tag :core
    test "emits start and stop for a successful query", %{conn: conn} do
      attach([[:bolty, :query, :start], [:bolty, :query, :stop]])

      assert {:ok, _response} = Bolty.query(conn, "RETURN 1 AS n")

      assert_receive {:telemetry, [:bolty, :query, :start], start_meas, start_meta}
      assert %{system_time: _, monotonic_time: _} = start_meas
      assert start_meta.db_system == "neo4j"
      assert start_meta.db_statement == "RETURN 1 AS n"

      assert_receive {:telemetry, [:bolty, :query, :stop], stop_meas, stop_meta}
      assert is_integer(stop_meas.duration)
      assert stop_meta.result == :ok
      refute Map.has_key?(stop_meta, :error)
    end

    @tag :core
    test "passes the :db option through as metadata", %{conn: conn} do
      attach([[:bolty, :query, :stop]])

      Bolty.query(conn, "RETURN 1 AS n", %{}, db: "neo4j")

      assert_receive {:telemetry, [:bolty, :query, :stop], _meas, %{db_instance: "neo4j"}}
    end

    @tag :core
    test "a server-side failure is a :stop with an {:error, _} result, not an :exception",
         %{conn: conn} do
      attach([[:bolty, :query, :stop], [:bolty, :query, :exception]])

      assert {:error, %Bolty.Error{}} = Bolty.query(conn, "NOT VALID CYPHER")

      assert_receive {:telemetry, [:bolty, :query, :stop], _meas, stop_meta}
      assert stop_meta.result == :error
      assert %Bolty.Error{} = stop_meta.error
      refute_received {:telemetry, [:bolty, :query, :exception], _, _}
    end
  end

  describe "connection lifecycle" do
    @tag :core
    test "emits connect on establish and disconnect on teardown" do
      attach([[:bolty, :connect], [:bolty, :disconnect]])

      {:ok, conn_data} = Connection.connect(@opts)

      assert_receive {:telemetry, [:bolty, :connect], connect_meas, connect_meta}
      assert is_integer(connect_meas.duration)
      assert is_float(connect_meta.bolt_version)
      assert is_bitstring(connect_meta.server_version)
      assert is_bitstring(connect_meta.connection_id)

      :ok = Connection.disconnect(:stop, conn_data)

      assert_receive {:telemetry, [:bolty, :disconnect], _meas, disconnect_meta}
      assert disconnect_meta.connection_id == connect_meta.connection_id
    end
  end
end
