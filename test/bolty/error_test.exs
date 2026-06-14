# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.ErrorTest do
  use ExUnit.Case, async: true

  alias Bolty.Error

  describe "Error.message/1" do
    @tag :core
    test "returns bolt.message when present" do
      error =
        Error.wrap(Bolty.BoltProtocol.Message.PullMessage, %{
          code: "Neo.ClientError.Statement.EntityNotFound",
          message: "Unable to load NODE with id 42"
        })

      assert Exception.message(error) == "Unable to load NODE with id 42"
    end

    @tag :core
    test "falls back to module.format_error/1 when bolt.message is absent" do
      error = Error.wrap(Bolty.BoltProtocol.Message.PullMessage, :unsupported_message_version)
      assert Exception.message(error) == "PULL message version not supported"
    end

    @tag :core
    test "falls back to safe string when module has no format_error/1 and bolt is nil" do
      error = %Error{module: Bolty.Client, code: :timeout}
      assert Exception.message(error) == "Bolty.Client error: :timeout"
    end

    @tag :core
    test "falls back to safe string when module is nil" do
      error = %Error{code: :unknown}
      assert Exception.message(error) == "nil error: :unknown"
    end
  end

  describe "PullMessage.format_error/1" do
    @tag :core
    test "formats :unsupported_message_version" do
      alias Bolty.BoltProtocol.Message.PullMessage

      assert PullMessage.format_error(:unsupported_message_version) ==
               "PULL message version not supported"
    end

    @tag :core
    test "formats unknown codes with a fallback" do
      alias Bolty.BoltProtocol.Message.PullMessage
      assert is_binary(PullMessage.format_error(:unknown))
      assert is_binary(PullMessage.format_error(:anything_else))
    end
  end
end
