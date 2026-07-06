# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Mix.Tasks.Test.MatrixTest do
  @moduledoc """
  Shadow test for the `mix test.matrix` per-version mapping. The task shells out
  to `mix test` (not exercised here), but the pure version -> {string, port}
  decision is testable in isolation — and regression-proofs it against changes
  to the internal version representation (which once broke the task silently).
  """
  use ExUnit.Case, async: true

  alias Mix.Tasks.Test.Matrix

  describe "version_env/3" do
    test "5.x versions use the default port and format as strings" do
      assert Matrix.version_env({5, 0}, "7687", "7689") == {"5.0", "7687"}
      assert Matrix.version_env({5, 8}, "7687", "7689") == {"5.8", "7687"}
    end

    test "6.x+ versions use the Bolt 6 port" do
      assert Matrix.version_env({6, 0}, "7687", "7689") == {"6.0", "7689"}
      assert Matrix.version_env({7, 2}, "7687", "7689") == {"7.2", "7689"}
    end

    test "renders the version as a string (a float would drop 5.10 -> 5.1)" do
      assert {"5.10", _} = Matrix.version_env({5, 10}, "7687", "7689")
    end
  end
end
