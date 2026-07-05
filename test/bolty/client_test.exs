# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.ClientTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Bolty.Client
  alias Bolty.BoltProtocol.Versions
  import Bolty.BoltProtocol.ServerResponse

  @opts Bolty.TestHelper.opts()
  @noop_chunk <<0x00, 0x00>>

  # Frame a message body the way Bolt does on the wire: one or more
  # [uint16 length][payload] chunks terminated by a zero-length (0x0000) chunk.
  # `framed/1` emits a single-chunk message; `body/1` strips the trailing 0x0000
  # the older fixtures baked into their payloads, leaving the true message body.
  defp framed(payload), do: [<<byte_size(payload)::16>>, payload, @noop_chunk]
  defp body(full), do: binary_part(full, 0, byte_size(full) - 2)

  defp handle_handshake(client, opts) do
    case client.bolt_version do
      version when version >= {5, 1} ->
        metadata = Client.send_hello(client, opts)
        Client.send_logon(client, opts)
        metadata

      _ ->
        Client.send_hello(client, opts)
    end
  end

  describe "connect" do
    @tag :bolt_version_5_3
    test "multiple versions specified — unsupported entries are dropped with a warning" do
      import ExUnit.CaptureLog

      opts = [versions: ["5.3", "4.0", "3.0"]] ++ @opts

      log =
        capture_log(fn ->
          assert {:ok, client} = Client.connect(opts)
          assert {5, 3} == client.bolt_version
        end)

      assert log =~ "dropping unsupported Bolt version"
      assert log =~ "4.0"
      assert log =~ "3.0"
    end

    @tag :bolt_version_5_3
    test "unordered versions specified" do
      opts = [versions: ["4.0", "3.0", "5.3"]] ++ @opts
      assert {:ok, client} = Client.connect(opts)
      assert {5, 3} == client.bolt_version
    end

    @tag :last_version
    test "no versions specified" do
      opts = [] ++ @opts
      assert {:ok, client} = Client.connect(opts)
      # With no `:versions`, the highest mutually-supported version is negotiated;
      # on the last_version job that is the newest version bolty supports.
      assert client.bolt_version == List.last(Versions.available_versions())
    end

    @tag core: true
    test "zero version is rejected at config time, not sent to the server" do
      opts = [versions: ["0.0"]] ++ @opts
      assert {:error, %Bolty.Error{code: :unsupported_versions}} = Client.connect(opts)
    end

    @tag core: true
    test "a version bolty doesn't implement is rejected at config time, not sent to the server" do
      opts = [versions: ["50.0"]] ++ @opts
      assert {:error, %Bolty.Error{code: :unsupported_versions}} = Client.connect(opts)
    end

    @tag core: true
    test ":versions with only unsupported entries returns a clean error listing them" do
      opts = [versions: ["3.0", "4.2"]] ++ @opts

      assert {:error, %Bolty.Error{code: :unsupported_versions, bolt: %{message: message}}} =
               Client.connect(opts)

      assert message =~ "3.0"
      assert message =~ "4.2"
    end

    @tag core: true
    test "a refused connection returns a wrapped %Bolty.Error{}, not a raw posix tuple" do
      # Nothing listens on this port, so :gen_tcp.connect returns {:error, :econnrefused};
      # #70 requires it surface as a %Bolty.Error{} rather than the bare atom.
      opts = [port: 65_533] ++ @opts

      assert {:error, %Bolty.Error{module: Bolty.Client, code: code}} = Client.connect(opts)
      assert is_atom(code)
    end
  end

  describe "recv_packets" do
    @tag :core
    test "recv_packets/3 decodes one message in one noop chunk" do
      chunk =
        <<177, 112, 163, 134, 115, 101, 114, 118, 101, 114, 140, 78, 101, 111, 52, 106, 47, 53,
          46, 49, 51, 46, 48, 141, 99, 111, 110, 110, 101, 99, 116, 105, 111, 110, 95, 105, 100,
          136, 98, 111, 108, 116, 45, 53, 49, 49, 133, 104, 105, 110, 116, 115, 162, 208, 31, 99,
          111, 110, 110, 101, 99, 116, 105, 111, 110, 46, 114, 101, 99, 118, 95, 116, 105, 109,
          101, 111, 117, 116, 95, 115, 101, 99, 111, 110, 100, 115, 120, 208, 17, 116, 101, 108,
          101, 109, 101, 116, 114, 121, 46, 101, 110, 97, 98, 108, 101, 100, 194, 0, 0>>

      pid = Bolty.Mocks.SockMock.start_link(framed(body(chunk)))
      client = %{sock: {Bolty.Mocks.SockMock, pid}, bolt_version: {1, 0}}
      {:ok, message} = Client.recv_packets(client, fn _bolt_version, data -> {:ok, data} end, 0)

      assert message == [
               {:success,
                %{
                  "connection_id" => "bolt-511",
                  "hints" => %{
                    "connection.recv_timeout_seconds" => 120,
                    "telemetry.enabled" => false
                  },
                  "server" => "Neo4j/5.13.0"
                }}
             ]
    end

    @tag :core
    test "recv_packets/3 decoded messages with an intermediate noob" do
      chunk1 = <<177, 113, 146, 201, 4, 0, 201, 8, 0, 0, 0>>

      chunk2 =
        <<177, 112, 163, 134, 115, 101, 114, 118, 101, 114, 140, 78, 101, 111, 52, 106, 47, 53,
          46, 49, 51, 46, 48, 141, 99, 111, 110, 110, 101, 99, 116, 105, 111, 110, 95, 105, 100,
          136, 98, 111, 108, 116, 45, 53, 49, 49, 133, 104, 105, 110, 116, 115, 162, 208, 31, 99,
          111, 110, 110, 101, 99, 116, 105, 111, 110, 46, 114, 101, 99, 118, 95, 116, 105, 109,
          101, 111, 117, 116, 95, 115, 101, 99, 111, 110, 100, 115, 120, 208, 17, 116, 101, 108,
          101, 109, 101, 116, 114, 121, 46, 101, 110, 97, 98, 108, 101, 100, 194, 0, 0>>

      pid = Bolty.Mocks.SockMock.start_link(framed(body(chunk1)) ++ framed(body(chunk2)))

      client = %{sock: {Bolty.Mocks.SockMock, pid}, bolt_version: {3, 0}}
      {:ok, message} = Client.recv_packets(client, fn _bolt_version, data -> {:ok, data} end, 0)

      assert message == [
               {:success,
                %{
                  "connection_id" => "bolt-511",
                  "hints" => %{
                    "connection.recv_timeout_seconds" => 120,
                    "telemetry.enabled" => false
                  },
                  "server" => "Neo4j/5.13.0"
                }},
               {:record, [1024, 2048]}
             ]
    end

    @tag :core
    test "ignores noop chunks between two chunks" do
      chunk1 = <<177, 113, 146, 201, 4, 0, 201, 8, 0, 0, 0>>

      chunk2 =
        <<177, 112, 163, 134, 115, 101, 114, 118, 101, 114, 140, 78, 101, 111, 52, 106, 47, 53,
          46, 49, 51, 46, 48, 141, 99, 111, 110, 110, 101, 99, 116, 105, 111, 110, 95, 105, 100,
          136, 98, 111, 108, 116, 45, 53, 49, 49, 133, 104, 105, 110, 116, 115, 162, 208, 31, 99,
          111, 110, 110, 101, 99, 116, 105, 111, 110, 46, 114, 101, 99, 118, 95, 116, 105, 109,
          101, 111, 117, 116, 95, 115, 101, 99, 111, 110, 100, 115, 120, 208, 17, 116, 101, 108,
          101, 109, 101, 116, 114, 121, 46, 101, 110, 97, 98, 108, 101, 100, 194, 0, 0>>

      pid =
        Bolty.Mocks.SockMock.start_link(
          [@noop_chunk] ++ framed(body(chunk1)) ++ [@noop_chunk] ++ framed(body(chunk2))
        )

      client = %{sock: {Bolty.Mocks.SockMock, pid}, bolt_version: {5, 0}}
      {:ok, message} = Client.recv_packets(client, fn _bolt_version, data -> {:ok, data} end, 0)

      assert message == [
               {:success,
                %{
                  "connection_id" => "bolt-511",
                  "hints" => %{
                    "connection.recv_timeout_seconds" => 120,
                    "telemetry.enabled" => false
                  },
                  "server" => "Neo4j/5.13.0"
                }},
               {:record, [1024, 2048]}
             ]
    end

    @tag :core
    test "reassembles a single message split across multiple chunks (#57)" do
      # One RECORD body split across two data chunks with no terminator between
      # them, followed by an empty SUCCESS summary. The old reader assumed one
      # chunk per message and desynced on the second chunk's size header.
      record = <<177, 113, 146, 201, 4, 0, 201, 8, 0>>
      head = binary_part(record, 0, 5)
      tail = binary_part(record, 5, byte_size(record) - 5)
      success = <<177, 112, 160>>

      frames =
        [<<byte_size(head)::16>>, head, <<byte_size(tail)::16>>, tail, @noop_chunk] ++
          framed(success)

      pid = Bolty.Mocks.SockMock.start_link(frames)
      client = %{sock: {Bolty.Mocks.SockMock, pid}, bolt_version: {5, 0}}
      {:ok, message} = Client.recv_packets(client, fn _bolt_version, data -> {:ok, data} end, 0)

      assert message == [{:success, %{}}, {:record, [1024, 2048]}]
    end
  end

  describe "run_statement" do
    @tag :core
    test "simple query" do
      assert {:ok, client} = Client.connect(@opts)
      handle_handshake(client, @opts)

      query = "RETURN 1024 AS a, 2048 AS b"

      {:ok,
       statement_result(
         result_run: result_run,
         result_pull: result_pull,
         query: query_result
       )} = Client.run_statement(client, query, %{}, %{})

      assert query_result == query
      assert %{"fields" => ["a", "b"], "t_first" => _} = result_run

      assert pull_result(records: records, success_data: success_data) = result_pull
      assert %{"t_last" => _, "type" => "r"} = success_data
      assert [[1024, 2048]] == records
    end

    @tag core: true
    test "simple query with parameters" do
      assert {:ok, client} = Client.connect(@opts)
      handle_handshake(client, @opts)

      query = "RETURN 4 + $number AS result"

      {:ok,
       statement_result(
         result_run: result_run,
         result_pull: result_pull,
         query: query_result
       )} = Client.run_statement(client, query, %{number: 5}, %{})

      assert query_result == query
      assert %{"fields" => ["result"], "t_first" => _} = result_run

      assert pull_result(records: records, success_data: success_data) = result_pull
      assert %{"t_last" => _, "type" => "r"} = success_data
      assert [[9]] == records
    end

    @tag core: true
    test "simple range query" do
      assert {:ok, client} = Client.connect(@opts)
      handle_handshake(client, @opts)

      query = "UNWIND range(1, 10) AS n RETURN n"

      {:ok,
       statement_result(
         result_run: result_run,
         result_pull: result_pull,
         query: query_result
       )} = Client.run_statement(client, query, %{}, %{})

      assert query_result == query
      assert %{"fields" => ["n"], "t_first" => _} = result_run

      assert pull_result(records: records, success_data: success_data) = result_pull
      assert %{"t_last" => _, "type" => "r"} = success_data
      assert [[1], [2], [3], [4], [5], [6], [7], [8], [9], [10]] == records
    end

    @tag :bolt_5_x
    test "simple query with wrong extra parameters" do
      assert {:ok, client} = Client.connect(@opts)
      handle_handshake(client, @opts)

      query = "RETURN 1024 AS a, 2048 AS b"

      {:error, %Bolty.Error{code: :request_invalid}} =
        Client.run_statement(client, query, %{}, %{n: %{d: 4}})
    end

    @tag :core
    test "get all nodes" do
      assert {:ok, client} = Client.connect(@opts)
      handle_handshake(client, @opts)

      query = "MATCH(n) RETURN n"
      result = Client.run_statement(client, query, %{}, %{})

      {:ok,
       statement_result(
         result_run: result_run,
         result_pull: result_pull,
         query: _
       )} = result

      assert %{"fields" => ["n"], "t_first" => _} = result_run

      assert pull_result(records: _, success_data: success_data) = result_pull
      assert %{"t_last" => _, "type" => "r"} = success_data
    end
  end

  describe "Explicit Transaction" do
    @tag :core
    test "simple begin message" do
      assert {:ok, client} = Client.connect(@opts)
      handle_handshake(client, @opts)
      assert {:ok, _} = Client.send_begin(client, %{})
    end

    @tag :core
    test "simple commit message" do
      assert {:ok, client} = Client.connect(@opts)
      handle_handshake(client, @opts)

      assert {:ok, _} = Client.send_begin(client, %{})
      assert {:ok, _} = Client.send_commit(client)
    end

    @tag :bolt_5_x
    test "simple commit message without starting a transaction" do
      assert {:ok, client} = Client.connect(@opts)
      handle_handshake(client, @opts)

      assert {:error, %Bolty.Error{code: :request_invalid}} = Client.send_commit(client)
    end

    @tag :core
    test "simple rollback message" do
      assert {:ok, client} = Client.connect(@opts)
      handle_handshake(client, @opts)

      assert {:ok, _} = Client.send_begin(client, %{})
      assert {:ok, _} = Client.send_rollback(client)
    end

    @tag :bolt_5_x
    test "simple rollback message without starting a transaction" do
      assert {:ok, client} = Client.connect(@opts)
      handle_handshake(client, @opts)

      assert {:error, %Bolty.Error{code: :request_invalid}} = Client.send_rollback(client)
    end
  end

  describe "pull message" do
    @tag :core
    test "ok send_pull" do
      assert {:ok, client} = Client.connect(@opts)
      handle_handshake(client, @opts)

      {:ok, %{"fields" => ["num"], "t_first" => _}} =
        Client.send_run(client, "RETURN 1 as num", %{}, %{})

      {:ok, {:pull_result, [[1]], %{"t_last" => _, "type" => "r"}}} =
        Client.send_pull(client, %{})
    end
  end

  describe "reset message" do
    @tag :bolt_5_x
    test "ok send_reset" do
      assert {:ok, client} = Client.connect(@opts)
      handle_handshake(client, @opts)

      assert {:ok, _} = Client.run_statement(client, "RETURN 1 as num", %{}, %{})
      assert {:ok, _} = Client.send_reset(client)
    end

    @tag :bolt_5_x
    test "allows to recover from error with send_reset" do
      assert {:ok, client} = Client.connect(@opts)
      handle_handshake(client, @opts)

      assert {:error, _} = Client.run_statement(client, "Invalid cypher", %{}, %{})
      assert {:ok, _} = Client.send_reset(client)

      assert {:ok, _} = Client.run_statement(client, "RETURN 1 as num", %{}, %{})
    end
  end

  describe "goodbye message" do
    @tag :bolt_5_x
    test "goodbye/1" do
      assert {:ok, client} = Client.connect(@opts)
      handle_handshake(client, @opts)

      assert :ok = Client.send_goodbye(client)
    end
  end

  describe "discard message:" do
    @tag :core
    test "discard_all/2 (successful)" do
      assert {:ok, client} = Client.connect(@opts)
      handle_handshake(client, @opts)

      {:ok, _} = Client.send_run(client, "RETURN 1 as num", %{}, %{})

      assert {:ok, %{"t_last" => _, "type" => "r"}} = Client.send_discard(client, %{})
    end
  end

  describe "Hello Message:" do
    @tag :bolt_5_x
    test "send_hello/1 (successful)" do
      assert {:ok, client} = Client.connect(@opts)
      assert {:ok, %{"connection_id" => _, "hints" => _}} = Client.send_hello(client, @opts)
    end
  end

  describe "Logoff Message:" do
    @tag :bolt_version_5_1
    @tag :bolt_version_5_2
    @tag :bolt_version_5_3
    @tag :bolt_version_5_4
    test "send_logoff/1 (successful)" do
      assert {:ok, client} = Client.connect(@opts)
      Client.send_hello(client, @opts)
      Client.send_logon(client, @opts)

      assert {:ok, _} = Client.send_logoff(client)
      assert {:ok, _} = Client.send_logon(client, @opts)
    end
  end

  describe "Ping message:" do
    @tag :core
    test "send_ping/1 (successful)" do
      assert {:ok, client} = Client.connect(@opts)
      handle_handshake(client, @opts)

      assert {:ok, true} = Client.send_ping(client)
    end

    @tag :bolt_5_x
    test "send_ping/1 (failure)" do
      opts = @opts ++ [pool_size: 1]
      assert {:ok, client} = Client.connect(opts)
      {:ok, server_metadata} = handle_handshake(client, @opts)

      Client.run_statement(
        client,
        "CALL dbms.killConnection($connection_id)",
        %{connection_id: server_metadata["connection_id"]},
        %{}
      )

      assert {:error, :db_ping_failed} = Client.send_ping(client)
    end
  end
end
