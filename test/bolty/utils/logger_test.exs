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

  # Excluded as another test has a long result and therefore a long hex and slow down tests
  # test "Log hex data" do
  #   assert capture_log(fn -> Logger.log_message(:client, :success, <<0x01, 0xAF>>, :hex) end) =~
  #            "C: SUCCESS ~ <<0x1, 0xAF>>"
  # end
end
