# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.BoltProtocol.MessageDecoderTest do
  use ExUnit.Case, async: true

  alias Bolty.BoltProtocol.MessageDecoder
  @moduletag :core

  describe "Decode common messages:" do
    test "SUCCESS" do
      success_hex =
        <<0xB1, 0x70, 0xA1, 0x86, 0x73, 0x65, 0x72, 0x76, 0x65, 0x72, 0x8B, 0x4E, 0x65, 0x6F,
          0x34, 0x6A, 0x2F, 0x33, 0x2E, 0x34, 0x2E, 0x31>>

      assert MessageDecoder.decode(success_hex) == {:success, %{"server" => "Neo4j/3.4.1"}}
    end

    test "FAILURE" do
      failure_hex =
        <<0xB1, 0x7F, 0xA2, 0x84, 0x63, 0x6F, 0x64, 0x65, 0xD0, 0x25, 0x4E, 0x65, 0x6F, 0x2E,
          0x43, 0x6C, 0x69, 0x65, 0x6E, 0x74, 0x45, 0x72, 0x72, 0x6F, 0x72, 0x2E, 0x53, 0x65,
          0x63, 0x75, 0x72, 0x69, 0x74, 0x79, 0x2E, 0x55, 0x6E, 0x61, 0x75, 0x74, 0x68, 0x6F,
          0x72, 0x69, 0x7A, 0x65, 0x64, 0x87, 0x6D, 0x65, 0x73, 0x73, 0x61, 0x67, 0x65, 0xD0,
          0x39, 0x54, 0x68, 0x65, 0x20, 0x63, 0x6C, 0x69, 0x65, 0x6E, 0x74, 0x20, 0x69, 0x73,
          0x20, 0x75, 0x6E, 0x61, 0x75, 0x74, 0x68, 0x6F, 0x72, 0x69, 0x7A, 0x65, 0x64, 0x20,
          0x64, 0x75, 0x65, 0x20, 0x74, 0x6F, 0x20, 0x61, 0x75, 0x74, 0x68, 0x65, 0x6E, 0x74,
          0x69, 0x63, 0x61, 0x74, 0x69, 0x6F, 0x6E, 0x20, 0x66, 0x61, 0x69, 0x6C, 0x75, 0x72,
          0x65, 0x2E>>

      failure =
        {:failure,
         %{
           "code" => "Neo.ClientError.Security.Unauthorized",
           "message" => "The client is unauthorized due to authentication failure."
         }}

      assert MessageDecoder.decode(failure_hex) == failure
    end

    test "RECORD" do
      assert MessageDecoder.decode(<<0xB1, 0x71, 0x91, 0x1>>) == {:record, [1]}
    end

    test "IGNORED" do
      assert {:ignored, _} = MessageDecoder.decode(<<0xB0, 0x7E>>)
    end
  end

  describe "FAILURE → %Bolty.Error{}" do
    # Captured verbatim from Neo4j 2026.06 for `CALL db.nope()`. `description` is
    # the boilerplate for GQLSTATUS 42001 — identical for every 42001 — while
    # `message` is the diagnostic that names the procedure (issue #138).
    @gql_failure %{
      "gql_status" => "42001",
      "description" => "error: syntax error or access rule violation - invalid syntax",
      "message" =>
        "There is no procedure with the name `db.nope` registered for this database " <>
          "instance. Please ensure you've spelled the procedure name correctly.",
      "neo4j_code" => "Neo.ClientError.Procedure.ProcedureNotFound",
      "diagnostic_record" => %{"_classification" => "CLIENT_ERROR"},
      "cause" => %{
        "gql_status" => "42N08",
        "description" => "error: syntax error or access rule violation - no such procedure.",
        "message" => "42N08: The procedure db.nope() was not found.",
        "diagnostic_record" => %{"_classification" => "CLIENT_ERROR"}
      }
    }

    test "surfaces the diagnostic message, not the GQLSTATUS boilerplate" do
      assert %Bolty.Error{bolt: bolt} = MessageDecoder.failure_error(SomeModule, @gql_failure)
      assert bolt.message =~ "no procedure with the name `db.nope`"
      assert bolt.description == "error: syntax error or access rule violation - invalid syntax"
    end

    test "Exception.message/1 reports the diagnostic too" do
      error = MessageDecoder.failure_error(SomeModule, @gql_failure)
      assert Exception.message(error) =~ "no procedure with the name `db.nope`"
    end

    test "keeps the GQL fields rather than discarding them" do
      assert %Bolty.Error{bolt: bolt} = MessageDecoder.failure_error(SomeModule, @gql_failure)
      assert bolt.code == "Neo.ClientError.Procedure.ProcedureNotFound"
      assert bolt.gql_status == "42001"
      assert bolt.diagnostic_record == %{"_classification" => "CLIENT_ERROR"}
    end

    test "normalises the cause chain to the same shape" do
      assert %Bolty.Error{bolt: %{cause: cause}} =
               MessageDecoder.failure_error(SomeModule, @gql_failure)

      assert cause.gql_status == "42N08"
      assert cause.message == "42N08: The procedure db.nope() was not found."
      assert cause.description =~ "no such procedure"
    end

    test "a legacy pre-5.7 FAILURE keeps working, with no GQL keys invented" do
      legacy = %{
        "code" => "Neo.ClientError.Security.Unauthorized",
        "message" => "The client is unauthorized due to authentication failure."
      }

      assert %Bolty.Error{code: :unauthorized, bolt: bolt} =
               MessageDecoder.failure_error(SomeModule, legacy)

      assert bolt.message == "The client is unauthorized due to authentication failure."
      refute Map.has_key?(bolt, :gql_status)
      refute Map.has_key?(bolt, :description)
      refute Map.has_key?(bolt, :cause)
    end

    test "falls back to description when a server sends no message" do
      failure = %{
        "neo4j_code" => "Neo.ClientError.Statement.SyntaxError",
        "gql_status" => "42001",
        "description" => "error: syntax error or access rule violation - invalid syntax"
      }

      assert %Bolty.Error{bolt: bolt} = MessageDecoder.failure_error(SomeModule, failure)
      assert bolt.message == "error: syntax error or access rule violation - invalid syntax"
    end
  end
end
