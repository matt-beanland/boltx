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
      version when version >= 5.1 ->
        metadata = Client.send_hello(client, opts)
        Client.send_logon(client, opts)
        metadata

      _ ->
        Client.send_hello(client, opts)
    end
  end

  describe "Client configuration" do
    @describetag :core

    test "parsing the host, schema and the port, from a uri string config parameter" do
      opts = [
        uri: "bolt://hobby-happyHoHoHo.dbs.graphenedb.com:24786",
        auth: [username: "usertest"]
      ]

      assert {:ok, config} = Client.Config.new(opts)

      assert config.hostname == "hobby-happyHoHoHo.dbs.graphenedb.com"
      assert config.scheme == "bolt"
      assert config.port == 24786
      assert config.username == "usertest"
    end

    test "standard Bolty default configuration for port, hostname and schema" do
      opts = [
        auth: [username: "usertest"]
      ]

      assert {:ok, config} = Client.Config.new(opts)

      assert config.hostname == "localhost"
      assert config.port == 7687
      assert config.scheme == "bolt+s"
      assert config.username == "usertest"
    end

    test "parsing the host, scheme and the port without uri" do
      opts = [
        hostname: "hobby-happyHoHoHo.dbs.com",
        scheme: "bolt+s",
        port: 7689,
        auth: [username: "usertests"]
      ]

      assert {:ok, config} = Client.Config.new(opts)

      assert config.hostname == "hobby-happyHoHoHo.dbs.com"
      assert config.scheme == "bolt+s"
      assert config.port == 7689
      assert config.username == "usertests"
    end

    test "explicit :hostname/:port/:scheme opts take priority over URI components" do
      opts = [
        uri: "bolt://hobby-happyHoHoHo.dbs.graphenedb.com:24786",
        hostname: "happy.com",
        scheme: "neo4j",
        port: 7689,
        auth: [username: "usertests"]
      ]

      assert {:ok, config} = Client.Config.new(opts)

      # 0.3.0: explicit opts win over URI (the previous behaviour was the reverse).
      assert config.hostname == "happy.com"
      assert config.scheme == "neo4j"
      assert config.port == 7689
      assert config.username == "usertests"
    end

    test "missing :username returns a %Bolty.Error{}, does not raise" do
      assert {:error, %Bolty.Error{module: Bolty.Client, code: :missing_username}} =
               Client.Config.new(hostname: "localhost")
    end

    test "the password is redacted when the config is inspected" do
      {:ok, config} = Client.Config.new(auth: [username: "u", password: "s3cret"])
      refute inspect(config) =~ "s3cret"
    end

    test "maps schemes to the correct TLS verification intent" do
      base_opts = [
        auth: [username: "usertests"]
      ]

      opts1 = base_opts ++ [scheme: "bolt"]

      assert {:ok, %Client.Config{scheme: "bolt", ssl?: false, tls_verify: :none}} =
               Client.Config.new(opts1)

      # +s -> full verification (previously, and incorrectly, :verify_none)
      opts2 = base_opts ++ [scheme: "bolt+s"]

      assert {:ok, %Client.Config{scheme: "bolt+s", ssl?: true, tls_verify: :verify}} =
               Client.Config.new(opts2)

      # +ssc -> self-signed / trust-all (previously, and incorrectly, :verify_peer)
      opts3 = base_opts ++ [scheme: "bolt+ssc"]

      assert {:ok, %Client.Config{scheme: "bolt+ssc", ssl?: true, tls_verify: :self_signed}} =
               Client.Config.new(opts3)

      opts4 = base_opts ++ [scheme: "neo4j"]

      assert {:ok, %Client.Config{scheme: "neo4j", ssl?: false, tls_verify: :none}} =
               Client.Config.new(opts4)

      opts5 = base_opts ++ [scheme: "neo4j+s"]

      assert {:ok, %Client.Config{scheme: "neo4j+s", ssl?: true, tls_verify: :verify}} =
               Client.Config.new(opts5)

      opts6 = base_opts ++ [scheme: "neo4j+ssc"]

      assert {:ok, %Client.Config{scheme: "neo4j+ssc", ssl?: true, tls_verify: :self_signed}} =
               Client.Config.new(opts6)
    end

    test "preserves user-supplied :ssl_opts verbatim (no override at config time)" do
      opts = [
        auth: [username: "usertests"],
        scheme: "bolt+s",
        ssl_opts: [verify: :verify_peer, cacertfile: "/etc/ssl/my_ca.pem"]
      ]

      # The strict defaults are materialised at connect time; Config keeps the
      # user's opts raw so they can be merged *over* the defaults (user wins).
      assert {:ok,
              %Client.Config{
                tls_verify: :verify,
                ssl_opts: [verify: :verify_peer, cacertfile: "/etc/ssl/my_ca.pem"]
              }} = Client.Config.new(opts)
    end
  end

  describe "build_tls_opts/4" do
    @describetag :core
    @socket_opts [mode: :binary, packet: :raw, active: false]

    test ":verify builds strict, secure-by-default TLS options" do
      opts = Client.build_tls_opts(:verify, "graph.example.com", [], @socket_opts)

      assert opts[:verify] == :verify_peer
      assert opts[:server_name_indication] == ~c"graph.example.com"

      assert opts[:customize_hostname_check] == [
               match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
             ]

      # CA trust anchors sourced from the OS store, not an empty/absent list.
      assert is_list(opts[:cacerts]) and opts[:cacerts] != []
    end

    test ":self_signed encrypts without verification" do
      opts = Client.build_tls_opts(:self_signed, "localhost", [], @socket_opts)

      assert opts[:verify] == :verify_none
      assert opts[:server_name_indication] == ~c"localhost"
      refute Keyword.has_key?(opts, :cacerts)
    end

    test "user :ssl_opts override the strict defaults (user wins)" do
      user = [verify: :verify_none, cacertfile: "/etc/ssl/my_ca.pem"]
      opts = Client.build_tls_opts(:verify, "graph.example.com", user, @socket_opts)

      # The security-critical guarantee: an explicit user override is honoured
      # rather than being silently forced back to the default.
      assert opts[:verify] == :verify_none
      assert opts[:cacertfile] == "/etc/ssl/my_ca.pem"
    end

    test "a user :cacertfile is honoured, not clobbered by the default :cacerts" do
      # :cacerts and :cacertfile are mutually exclusive in :ssl (:cacerts wins);
      # injecting the default OS trust store unconditionally would silently
      # ignore the user's CA file. verify stays :verify_peer here.
      user = [cacertfile: "/etc/ssl/my_ca.pem"]
      opts = Client.build_tls_opts(:verify, "graph.example.com", user, @socket_opts)

      assert opts[:verify] == :verify_peer
      assert opts[:cacertfile] == "/etc/ssl/my_ca.pem"
      refute Keyword.has_key?(opts, :cacerts)
    end

    test "transport socket options stay authoritative over user :ssl_opts" do
      user = [mode: :something_else]
      opts = Client.build_tls_opts(:verify, "graph.example.com", user, @socket_opts)

      assert opts[:mode] == :binary
    end
  end

  describe "connect" do
    @tag :bolt_version_5_3
    test "multiple versions specified" do
      opts = [versions: [5.3, 4, 3]] ++ @opts
      assert {:ok, client} = Client.connect(opts)
      assert 5.3 == client.bolt_version
    end

    @tag :bolt_version_5_3
    test "unordered versions specified" do
      opts = [versions: [4, 3, 5.3]] ++ @opts
      assert {:ok, client} = Client.connect(opts)
      assert 5.3 == client.bolt_version
    end

    @tag :last_version
    test "no versions specified" do
      opts = [] ++ @opts
      assert {:ok, client} = Client.connect(opts)
      # latest_versions/0 returns ranged tuples like `{5, 0..4}`; the
      # negotiated `client.bolt_version` is the latest float in that range.
      {major, minor_or_range} = hd(Versions.latest_versions())

      minor =
        case minor_or_range do
          %Range{} = r -> List.last(Range.to_list(r))
          m when is_integer(m) -> m
        end

      assert major + minor / 10 == client.bolt_version
    end

    @tag core: true
    test "zero version" do
      opts = [versions: [0]] ++ @opts
      {:error, %Bolty.Error{code: :version_negotiation_error}} = Client.connect(opts)
    end

    @tag core: true
    test "major version incompatible with the server" do
      opts = [versions: [50]] ++ @opts
      {:error, %Bolty.Error{code: :version_negotiation_error}} = Client.connect(opts)
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
      client = %{sock: {Bolty.Mocks.SockMock, pid}, bolt_version: 1.0}
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

      client = %{sock: {Bolty.Mocks.SockMock, pid}, bolt_version: 3.0}
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

      client = %{sock: {Bolty.Mocks.SockMock, pid}, bolt_version: 5.0}
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
      client = %{sock: {Bolty.Mocks.SockMock, pid}, bolt_version: 5.0}
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
