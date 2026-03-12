defmodule Bolty.BoltProtocol.Message.ResetMessageTest do
  use ExUnit.Case, async: true

  alias Bolty.BoltProtocol.Message.ResetMessage

  describe "ResetMessage.encode/1" do
    @tag :core
    test "coding with version >= 3.0 of bolt" do
      bolt_version = 3.0
      assert <<0, 2, 176, 15, 0, 0>> == ResetMessage.encode(bolt_version)
    end

    @tag :core
    test "coding with version <= 2 of bolt" do
      bolt_version = 2.0

      assert {:error,
              %Bolty.Error{
                module: Bolty.BoltProtocol.Message.ResetMessage,
                bolt: %{code: :unsupported_message_version}
              }} = ResetMessage.encode(bolt_version)
    end

    @tag :core
    test "coding with version integer" do
      bolt_version = 1

      assert {:error,
              %Bolty.Error{
                module: Bolty.BoltProtocol.Message.ResetMessage,
                bolt: %{code: :unsupported_message_version}
              }} = ResetMessage.encode(bolt_version)
    end
  end
end
