# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.Utils.LoggerTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  alias Bolty.Utils.Logger
  @moduletag :core

  test "Log from formed message" do
    assert capture_log(fn -> Logger.log_message(:client, {:success, %{data: "ok"}}) end) =~
             "C: SUCCESS ~ %{data: \"ok\"}"
  end

  test "Log from non-formed message" do
    assert capture_log(fn -> Logger.log_message(:client, :success, %{data: "ok"}) end) =~
             "C: SUCCESS ~ %{data: \"ok\"}"
  end

  test "redacts auth credentials from a logged message body" do
    body = [%{scheme: "basic", principal: "neo4j", credentials: "supersecret"}]

    log = capture_log(fn -> Logger.log_message(:client, :message_type, body) end)

    refute log =~ "supersecret"
    assert log =~ "credentials: \"[REDACTED]\""
    assert log =~ "principal: \"neo4j\""
  end

  test "redacts nested credentials but leaves query-param structs intact" do
    body = [%{outer: %{credentials: "supersecret"}, params: %URI{host: "keepme"}}]

    log = capture_log(fn -> Logger.log_message(:client, :message_type, body) end)

    refute log =~ "supersecret"
    assert log =~ "[REDACTED]"
    assert log =~ "keepme"
  end

  describe "log_client_message_hex/2" do
    setup do
      Application.put_env(:bolty, :log_hex, true)
      on_exit(fn -> Application.put_env(:bolty, :log_hex, false) end)
    end

    test "suppresses the hex dump when the body carries credentials" do
      body = [%{scheme: "basic", principal: "neo4j", credentials: "supersecret"}]
      encoded = <<0x68, 0x75, 0x6E, 0x74>>

      log = capture_log(fn -> Logger.log_client_message_hex(encoded, body) end)

      assert log =~ "[hex suppressed: contains credentials]"
      refute log =~ "0x68"
    end

    test "dumps hex for a body with no secret fields" do
      body = [%{query: "RETURN 1"}]
      encoded = <<0x01, 0xAF>>

      log = capture_log(fn -> Logger.log_client_message_hex(encoded, body) end)

      assert log =~ "0x1"
      assert log =~ "0xAF"
    end
  end

  # Excluded as another test has a long result and therefore a long hex and slow down tests
  # test "Log hex data" do
  #   assert capture_log(fn -> Logger.log_message(:client, :success, <<0x01, 0xAF>>, :hex) end) =~
  #            "C: SUCCESS ~ <<0x1, 0xAF>>"
  # end
end
