# SPDX-FileCopyrightText: 2025 bolty contributors
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

  describe "Error.wrap/2 tuple handling (#110)" do
    @tag :core
    test "a {:tls_alert, ...} reason is wrapped, not left to raise on a bare tuple" do
      error =
        Error.wrap(Bolty.Client, {:tls_alert, {:certificate_expired, ~c"certificate expired"}})

      assert %Error{code: :tls_alert, bolt: %{message: message}} = error
      assert message =~ "certificate_expired"
      assert message =~ "certificate expired"
    end

    @tag :core
    test "any other tuple reason is wrapped with the raw reason preserved for diagnosis" do
      error = Error.wrap(Bolty.Client, {:some_reason, :nested})

      assert %Error{code: :connect_error, bolt: %{message: message}} = error
      assert message =~ "some_reason"
    end
  end

  describe "Error.to_atom/1 status-code mapping (#54)" do
    @tag :core
    test "maps the curated Neo4j status codes to stable atoms" do
      assert Error.to_atom("Neo.ClientError.Security.Unauthorized") == :unauthorized
      assert Error.to_atom("Neo.ClientError.Request.Invalid") == :request_invalid
      assert Error.to_atom("Neo.ClientError.Statement.SyntaxError") == :syntax_error
      assert Error.to_atom("Neo.ClientError.Statement.SemanticError") == :semantic_error
      assert Error.to_atom("Neo.ClientError.Statement.ArithmeticError") == :arithmetic_error
      assert Error.to_atom("Neo.ClientError.Statement.ParameterMissing") == :parameter_missing

      assert Error.to_atom("Neo.ClientError.Schema.ConstraintValidationFailed") ==
               :constraint_validation_failed

      assert Error.to_atom("Neo.TransientError.Transaction.DeadlockDetected") ==
               :deadlock_detected
    end

    @tag :core
    test "unmapped codes resolve to :unknown but keep the raw status on bolt.code" do
      assert Error.to_atom("Neo.ClientError.Statement.NotInMap") == :unknown

      error =
        Error.wrap(Bolty.Client, %{
          code: "Neo.ClientError.Statement.NotInMap",
          message: "boom"
        })

      assert error.code == :unknown
      assert error.bolt.code == "Neo.ClientError.Statement.NotInMap"
    end

    @tag :core
    test "an already-resolved atom passes through unchanged" do
      assert Error.to_atom(:constraint_validation_failed) == :constraint_validation_failed
      assert Error.to_atom(:unknown) == :unknown
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
