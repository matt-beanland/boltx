# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.BoltProtocol.Message.MessageEncoderTest do
  use ExUnit.Case, async: true

  alias Bolty.BoltProtocol.Message.{
    BeginMessage,
    CommitMessage,
    DiscardMessage,
    GoodbyeMessage,
    HelloMessage,
    RollbackMessage,
    PullMessage,
    ResetMessage,
    RunMessage
  }

  @moduletag :core

  defmodule TestUser do
    defstruct name: "", bolty: true
  end

  describe "Encode HELLO" do
    test "without params" do
      assert <<0x0, _, 0xB1, 0x1, _::binary>> = HelloMessage.encode({5, 0}, [])
    end

    test "with params" do
      assert <<0x0, _, 0xB1, 0x1, _::binary>> =
               HelloMessage.encode({5, 0}, user_agent: "user_agent_test")
    end

    test "with auth" do
      assert <<_, _, _, 0x01, _::binary>> =
               HelloMessage.encode({5, 0}, auth: [username: "hello", password: "hellopw"])
    end

    test "includes the routing field when set (SSR), on both the 5.0 and 5.1+ paths" do
      routing = %{"address" => "cluster.example.com:7687"}

      for bolt_version <- [{5, 0}, {5, 4}] do
        encoded = HelloMessage.encode(bolt_version, auth: [username: "u"], routing: routing)

        assert :binary.match(encoded, "routing") != :nomatch
        assert :binary.match(encoded, "cluster.example.com:7687") != :nomatch
      end
    end

    test "omits the routing field when not set" do
      encoded = HelloMessage.encode({5, 4}, auth: [username: "u"])

      assert :binary.match(encoded, "routing") == :nomatch
    end
  end

  describe "Encode BEGIN" do
    test "without params" do
      assert <<_, _, _, 0x11, _::binary>> = BeginMessage.encode({5, 0}, %{})
    end

    test "with params" do
      assert <<_, _, _, 0x11, _::binary>> = BeginMessage.encode({5, 0}, %{mode: "w"})
    end
  end

  describe "Encode COMMIT" do
    test "without params" do
      assert <<0x0, 0x2, 0xB0, 0x12, 0x0, 0x0>> == CommitMessage.encode({5, 0})
    end
  end

  describe "Encode DISCARD" do
    test "without params" do
      assert <<_, _, _, 0x2F, _::binary>> = DiscardMessage.encode({5, 0}, %{})
    end
  end

  describe "Encode GOODBYE" do
    test "without params" do
      assert <<_, _, _, 0x02, _::binary>> = GoodbyeMessage.encode({5, 0})
    end
  end

  describe "Encode ROLLBACK" do
    test "without params" do
      assert <<0x0, 0x2, 0xB0, 0x13, 0x0, 0x0>> = RollbackMessage.encode({5, 0})
    end
  end

  describe "Encode PULL" do
    test "without params" do
      assert <<_, _, _, 0x3F, _::binary>> = PullMessage.encode({5, 0}, %{})
    end
  end

  describe "Encode RESET" do
    test "without params" do
      assert <<0x0, 0x2, 0xB0, 0xF, 0x0, 0x0>> == ResetMessage.encode({5, 0})
    end
  end

  describe "Encode RUN" do
    test "without params" do
      assert <<0, 55, 179, 16, 143, 82, 69, 84, 85, 82, 78, 32, 49, 32, 65, 83, 32, 110, 117, 109,
               160, 164, 137, 98, 111, 111, 107, 109, 97, 114, 107, 115, 144, 130, 100, 98, 192,
               132, 109, 111, 100, 101, 129, 119, 139, 116, 120, 95, 109, 101, 116, 97, 100, 97,
               116, 97, 192, 0, 0>> ==
               RunMessage.encode({5, 0}, "RETURN 1 AS num", %{}, %{})
    end

    test "with params" do
      assert <<0, 64, 179, 16, 208, 18, 82, 69, 84, 85, 82, 78, 32, 36, 110, 117, 109, 32, 65, 83,
               32, 110, 117, 109, 161, 131, 110, 117, 109, 5, 164, 137, 98, 111, 111, 107, 109,
               97, 114, 107, 115, 144, 130, 100, 98, 192, 132, 109, 111, 100, 101, 129, 119, 139,
               116, 120, 95, 109, 101, 116, 97, 100, 97, 116, 97, 192, 0, 0>> ==
               RunMessage.encode({5, 0}, "RETURN $num AS num", %{num: 5}, %{})
    end

    test "with parameters encoding a structure" do
      query = "CREATE (n:User $props)"
      params = %{props: %TestUser{bolty: true, name: "Strut"}}

      assert <<0, 88, 179, 16, 208, 22, 67, 82, 69, 65, 84, 69, 32, 40, 110, 58, 85, 115, 101,
               114, 32, 36, 112, 114, 111, 112, 115, 41, 161, 133, 112, 114, 111, 112, 115, 162,
               133, 98, 111, 108, 116, 121, 195, 132, 110, 97, 109, 101, 133, 83, 116, 114, 117,
               116, 164, 137, 98, 111, 111, 107, 109, 97, 114, 107, 115, 144, 130, 100, 98, 192,
               132, 109, 111, 100, 101, 129, 119, 139, 116, 120, 95, 109, 101, 116, 97, 100, 97,
               116, 97, 192, 0, 0>> ==
               RunMessage.encode({5, 0}, query, params, %{})
    end
  end
end
