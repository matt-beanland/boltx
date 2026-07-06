# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.ConnectionRecoveryTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  import ExUnit.CaptureLog

  # Regression coverage for #54: a statement FAILURE must leave the pooled
  # connection usable (RESET back to READY) rather than stuck in the Bolt FAILED
  # state. Before the fix this produced an IGNORED rollback + a noisy `:ignored`
  # disconnect inside a transaction, and silently poisoned the pooled connection
  # for bare queries (every later checkout returned `:ignored` until it churned).
  #
  # Each test drives its own `pool_size: 1` pool so the same connection is reused
  # across checkouts — that is what makes a poisoned connection observable.

  @opts Bolty.TestHelper.opts()

  defp pool do
    {:ok, pool} = Bolty.start_link([pool_size: 1] ++ @opts)
    pool
  end

  describe "recovery after an in-transaction FAILURE (#54)" do
    @tag :core
    test "rolling back after a failed query neither disconnects nor leaves :ignored noise" do
      pool = pool()

      log =
        capture_log(fn ->
          result =
            Bolty.transaction(pool, fn conn ->
              assert {:error, %Bolty.Error{}} = Bolty.query(conn, "RETURN 1 / 0")
              Bolty.rollback(conn, :done)
            end)

          assert {:error, :done} = result
        end)

      refute log =~ ":ignored", "rollback over a FAILED connection must not surface :ignored"
      refute log =~ "disconnected", "an in-transaction failure must not force-disconnect"
    end

    @tag :core
    test "the connection is reusable after an in-transaction failure" do
      pool = pool()

      Bolty.transaction(pool, fn conn ->
        assert {:error, %Bolty.Error{}} = Bolty.query(conn, "RETURN 1 / 0")
        Bolty.rollback(conn, :done)
      end)

      assert {:ok, response} = Bolty.query(pool, "RETURN 7 AS n")
      assert [%{"n" => 7}] = response.results
    end

    @tag :core
    test "a constraint violation is classified and recovers cleanly (the ash_neo4j case)" do
      pool = pool()
      label = "RecoveryUniq#{System.unique_integer([:positive])}"

      # The named constraint is the only cross-test shared state; both conflicting
      # creates live inside the (rolled-back) transaction, so a concurrent global
      # node-wipe can't interfere. CREATE ... IF NOT EXISTS plus a DROP-by-name in an
      # `after` (runs even on failure; the pool is still alive, unlike on_exit) keep
      # it idempotent: System.unique_integer resets per VM, and the old schema-style
      # DROP errored on 5.x (silently, via non-bang query), so on a shared/persistent
      # DB constraints leaked and collided across runs (EquivalentSchemaRuleAlreadyExists).
      Bolty.query!(
        pool,
        "CREATE CONSTRAINT #{label} IF NOT EXISTS FOR (n:#{label}) REQUIRE n.k IS UNIQUE"
      )

      try do
        log =
          capture_log(fn ->
            Bolty.transaction(pool, fn conn ->
              assert {:ok, _} = Bolty.query(conn, "CREATE (:#{label} {k: 'x'})")

              assert {:error, %Bolty.Error{code: :constraint_validation_failed} = error} =
                       Bolty.query(conn, "CREATE (:#{label} {k: 'x'})")

              assert error.bolt.code == "Neo.ClientError.Schema.ConstraintValidationFailed"
              Bolty.rollback(conn, :done)
            end)
          end)

        refute log =~ ":ignored"
        refute log =~ "disconnected"

        # connection still usable
        assert {:ok, _} = Bolty.query(pool, "RETURN 1 AS n")
      after
        Bolty.query(pool, "DROP CONSTRAINT #{label} IF EXISTS")
      end
    end
  end

  describe "recovery after a bare-query FAILURE outside a transaction (#54)" do
    @tag :core
    test "a failed query does not poison later checkouts of the pooled connection" do
      pool = pool()

      assert {:error, %Bolty.Error{}} = Bolty.query(pool, "RETURN 1 / 0")

      for i <- 1..5 do
        assert {:ok, response} = Bolty.query(pool, "RETURN #{i} AS n"),
               "query #{i} after a failure should succeed, not hit a poisoned (:ignored) connection"

        assert [%{"n" => ^i}] = response.results
      end
    end
  end

  describe "the happy path is unaffected (#54)" do
    @tag :core
    test "a transaction with no failure still commits" do
      pool = pool()
      label = "Recovery#{System.unique_integer([:positive])}"

      # {:ok, :ok} is the regression guard: a clean transaction must run the commit
      # path (handle_commit -> :committed) and not the aborted-status guard added in
      # #54 — DBConnection turns that guard into {:error, :rollback}, not {:ok, :ok}.
      # Visibility is asserted *inside* the transaction; a follow-up read on a later
      # query can race the suite's async global truncate (MATCH (n) DETACH DELETE n
      # in bolty_test) deleting the committed node, which flakes (observed on CI).
      assert {:ok, :ok} =
               Bolty.transaction(pool, fn conn ->
                 assert {:ok, _} = Bolty.query(conn, "CREATE (:#{label} {k: 1})")

                 assert {:ok, response} =
                          Bolty.query(conn, "MATCH (n:#{label}) RETURN count(n) AS c")

                 assert [%{"c" => 1}] = response.results
                 :ok
               end)
    end
  end
end
