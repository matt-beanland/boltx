# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.ClientConfigTest do
  @moduledoc """
  Pure unit tests for Bolty.Client.Config — no live server needed. Split out of
  client_test.exs (#108): that module carries `@moduletag :integration`, which
  silently excluded these from a bare `mix test` even though they need no
  socket at all — including the P0-1 TLS-fix regression coverage, the riskiest
  change in the whole industrialisation effort. This module has no such tag,
  so it runs by default.
  """
  use ExUnit.Case, async: true

  alias Bolty.Client

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

    test "an unrecognised option key returns a clean error instead of a silent default (#121)" do
      assert {:error, %Bolty.Error{code: :invalid_option, bolt: %{message: message}}} =
               Client.Config.new(hostnam: "localhost", auth: [username: "u"])

      assert message =~ "hostnam"
    end

    test "every bolty start_option() key is accepted" do
      opts = [
        uri: "bolt://localhost:7687",
        hostname: "localhost",
        port: 7687,
        scheme: "bolt",
        versions: ["5.4"],
        auth: [username: "u", password: "p"],
        user_agent: "my_app/1.0",
        notifications_minimum_severity: "WARNING",
        notifications_disabled_categories: ["HINT"],
        ssl_opts: [],
        connect_timeout: 1_000,
        recv_timeout: 1_000,
        socket_options: []
      ]

      assert {:ok, %Client.Config{}} = Client.Config.new(opts)
    end

    test "DBConnection's own start options (e.g. :pool_size, :name) are accepted" do
      assert {:ok, %Client.Config{}} =
               Client.Config.new(
                 auth: [username: "u"],
                 pool_size: 5,
                 name: :my_bolty_pool,
                 after_connect: fn _ -> :ok end
               )
    end

    test "a key repeated with the same value (the override-by-prepending idiom) is silent" do
      import ExUnit.CaptureLog

      log =
        capture_log(fn ->
          assert {:ok, %Client.Config{port: 7687}} =
                   Client.Config.new(auth: [username: "u"], port: 7687, port: 7687)
        end)

      refute log =~ "multiple times"
    end

    test "a key repeated with conflicting values logs a warning, first occurrence wins" do
      import ExUnit.CaptureLog

      log =
        capture_log(fn ->
          assert {:ok, %Client.Config{port: 7687}} =
                   Client.Config.new(auth: [username: "u"], port: 7687, port: 9999)
        end)

      assert log =~ "option :port was passed multiple times with different values"
    end

    test "the password is redacted when the config is inspected" do
      {:ok, config} = Client.Config.new(auth: [username: "u", password: "s3cret"])
      refute inspect(config) =~ "s3cret"
    end

    test "parses string :versions to canonical tuples without warning" do
      import ExUnit.CaptureLog

      log =
        capture_log(fn ->
          {:ok, config} = Client.Config.new(auth: [username: "u"], versions: ["5.4", "6.0"])
          # canonical tuples, sorted desc, padded to the 4 handshake slots
          assert config.versions == [{6, 0}, {5, 4}, {0, 0}, {0, 0}]
        end)

      refute log =~ "deprecated"
    end

    test "accepts float :versions but logs a one-time deprecation warning" do
      import ExUnit.CaptureLog

      log =
        capture_log(fn ->
          {:ok, config} = Client.Config.new(auth: [username: "u"], versions: [5.4])
          assert config.versions == [{5, 4}, {0, 0}, {0, 0}, {0, 0}]
        end)

      assert log =~ "deprecated"
    end

    test "a range :versions entry that is fully supported is kept compact, no warning" do
      import ExUnit.CaptureLog

      log =
        capture_log(fn ->
          {:ok, config} = Client.Config.new(auth: [username: "u"], versions: [{5, 6..8}])
          # kept as one range slot, not expanded — every minor in it is supported
          assert config.versions == [{5, 6..8}, {0, 0}, {0, 0}, {0, 0}]
        end)

      refute log =~ "unsupported"
    end

    test "a range :versions entry spanning an unsupported minor is narrowed, with a warning" do
      import ExUnit.CaptureLog

      # {5, 5} doesn't exist in Versions.available_versions() (a real gap between
      # 5.4 and 5.6), so this range straddles a supported/unsupported boundary
      # exactly like a future version-floor bump would.
      log =
        capture_log(fn ->
          {:ok, config} = Client.Config.new(auth: [username: "u"], versions: [{5, 4..6}])
          assert config.versions == [{5, 6}, {5, 4}, {0, 0}, {0, 0}]
        end)

      assert log =~ "dropping unsupported Bolt version(s) 5.5"
    end

    test "surviving minors of a narrowed range are re-coalesced, not exploded into one slot each" do
      import ExUnit.CaptureLog

      # {5, 3..9} spans 7 minors; 5.5 and 5.9 don't exist in
      # Versions.available_versions(), leaving two contiguous survivor runs
      # (3..4 and 6..8). Only 4 handshake slots exist in total (pad_and_sort/1),
      # so if survivors were kept as flat individual tuples instead of being
      # re-ranged, this would need 5 slots and something would be silently
      # dropped by the Enum.take(4) padding step.
      log =
        capture_log(fn ->
          {:ok, config} = Client.Config.new(auth: [username: "u"], versions: [{5, 3..9}])
          assert config.versions == [{5, 6..8}, {5, 3..4}, {0, 0}, {0, 0}]
        end)

      assert log =~ "dropping unsupported Bolt version(s) 5.5, 5.9"
    end

    test "a range :versions entry with no supported minors is a config error" do
      assert {:error, %Bolty.Error{code: :unsupported_versions, bolt: %{message: message}}} =
               Client.Config.new(auth: [username: "u"], versions: [{3, 0..2}])

      assert message =~ "{3, 0..2}"
    end

    test "malformed :versions entries return a clean error instead of raising (#110)" do
      for bad <- ["abc", "5", "5.4.3", :atom, %{}, [1, 2]] do
        assert {:error, %Bolty.Error{code: :invalid_versions, bolt: %{message: message}}} =
                 Client.Config.new(auth: [username: "u"], versions: [bad]),
               "expected #{inspect(bad)} to return a clean error, not raise"

        assert message =~ inspect(bad)
      end
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

    test "a stray :ssl option is rejected as an unrecognised option (#107, #121)" do
      # The old :ssl boolean was removed as dead code; TLS derives entirely
      # from :scheme. It used to get a targeted warn-only exception carved out
      # of the general unknown-option handling (#107); now that #121 added
      # general unknown-option validation, :ssl no longer needs (or gets) that
      # special case — it's rejected the same way any other unrecognised key
      # is, rather than being silently accepted with just a log line.
      opts = [auth: [username: "usertests"], scheme: "bolt", ssl: true]

      assert {:error, %Bolty.Error{code: :invalid_option, bolt: %{message: message}}} =
               Client.Config.new(opts)

      assert message =~ "ssl"
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

  describe "server-side routing (:routing)" do
    @describetag :core

    test "neo4j schemes enable routing by default with the resolved address" do
      for scheme <- ~w(neo4j neo4j+s neo4j+ssc) do
        opts = [
          scheme: scheme,
          hostname: "cluster.example.com",
          port: 7687,
          auth: [username: "u"]
        ]

        assert {:ok, %Client.Config{routing: %{"address" => "cluster.example.com:7687"}}} =
                 Client.Config.new(opts)
      end
    end

    test "bolt schemes leave routing off by default" do
      for scheme <- ~w(bolt bolt+s bolt+ssc) do
        opts = [scheme: scheme, hostname: "single.example.com", port: 7687, auth: [username: "u"]]

        assert {:ok, %Client.Config{routing: nil}} = Client.Config.new(opts)
      end
    end

    test "routing: false opts a neo4j scheme out of routing" do
      opts = [scheme: "neo4j+s", hostname: "h", port: 7687, routing: false, auth: [username: "u"]]

      assert {:ok, %Client.Config{routing: nil}} = Client.Config.new(opts)
    end

    test "routing: true forces routing on a bolt scheme" do
      opts = [scheme: "bolt", hostname: "h", port: 7687, routing: true, auth: [username: "u"]]

      assert {:ok, %Client.Config{routing: %{"address" => "h:7687"}}} = Client.Config.new(opts)
    end

    test "the resolved address derives from URI components when not given explicitly" do
      opts = [uri: "neo4j://router.example.com:7999", auth: [username: "u"]]

      assert {:ok, %Client.Config{routing: %{"address" => "router.example.com:7999"}}} =
               Client.Config.new(opts)
    end

    test "an IPv6 literal host is bracketed in the address" do
      opts = [scheme: "neo4j", hostname: "::1", port: 7687, auth: [username: "u"]]

      assert {:ok, %Client.Config{routing: %{"address" => "[::1]:7687"}}} =
               Client.Config.new(opts)
    end

    test "a non-boolean :routing is a clean config error, not silently ignored" do
      opts = [scheme: "neo4j", routing: "yes", auth: [username: "u"]]

      assert {:error, %Bolty.Error{code: :invalid_routing, bolt: %{message: message}}} =
               Client.Config.new(opts)

      assert message =~ "must be true or false"
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
end
