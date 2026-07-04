# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.Utils.StatementSplitterTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Bolty.Utils.StatementSplitter

  describe "split/1 basics" do
    test "splits top-level statements and drops the terminator" do
      assert StatementSplitter.split("RETURN 1;\nRETURN 2") == ["RETURN 1", "RETURN 2"]
    end

    test "trailing semicolon is dropped, not sent as an empty statement" do
      assert StatementSplitter.split("RETURN 1;") == ["RETURN 1"]
    end

    test "empty segments between semicolons are skipped" do
      assert StatementSplitter.split("RETURN 1;;RETURN 2") == ["RETURN 1", "RETURN 2"]
    end

    test "each statement is trimmed" do
      assert StatementSplitter.split("  RETURN 1  ;  RETURN 2  ") == ["RETURN 1", "RETURN 2"]
    end

    test "empty and whitespace-only input yields no statements" do
      assert StatementSplitter.split("") == []
      assert StatementSplitter.split("   \n\t ") == []
    end
  end

  describe "split/1 does not split on `;` inside quoted contexts" do
    test "single-quoted string" do
      assert StatementSplitter.split("RETURN 'a;b' AS x") == ["RETURN 'a;b' AS x"]
    end

    test "double-quoted string" do
      assert StatementSplitter.split(~s|RETURN "a;b" AS x|) == [~s|RETURN "a;b" AS x|]
    end

    test "backslash-escaped quote keeps the string open" do
      # `\'` is an escaped quote, so the `;` is still inside the string literal.
      stmt = ~S|RETURN 'it\'s; fine'|
      assert StatementSplitter.split(stmt) == [stmt]
    end

    test "backtick-quoted identifier" do
      assert StatementSplitter.split("MATCH (n:`a;b`) RETURN n") == ["MATCH (n:`a;b`) RETURN n"]
    end

    test "doubled backtick escape inside an identifier" do
      stmt = "RETURN 1 AS `a``b;c`"
      assert StatementSplitter.split(stmt) == [stmt]
    end
  end

  describe "split/1 does not split on `;` inside comments" do
    test "line comment" do
      assert StatementSplitter.split("RETURN 1 // a;b\n + 2") == ["RETURN 1 // a;b\n + 2"]
    end

    test "block comment" do
      assert StatementSplitter.split("RETURN 1 /* a;b */ + 2") == ["RETURN 1 /* a;b */ + 2"]
    end

    test "comment-only trailing segment is dropped" do
      assert StatementSplitter.split("RETURN 1;\n// trailing comment\n") == ["RETURN 1"]
    end

    test "block-comment-only segment is dropped" do
      assert StatementSplitter.split("RETURN 1;/* just a note */") == ["RETURN 1"]
    end
  end

  describe "split/1 EOF handling" do
    test "unterminated string is flushed as one statement, not dropped or crashed" do
      assert StatementSplitter.split("RETURN 'oops") == ["RETURN 'oops"]
    end

    test "unterminated block comment is flushed" do
      assert StatementSplitter.split("RETURN 1 /* oops") == ["RETURN 1 /* oops"]
    end

    test "a trailing backslash inside a string does not crash" do
      assert StatementSplitter.split("RETURN 'a\\") == ["RETURN 'a\\"]
    end
  end

  # A `;`-free chunk of letters, optionally wrapping a single-quoted string that
  # may itself contain `;` and spaces. Starts and ends with letters so it is
  # already trimmed and unambiguously significant, and contains no top-level `;`,
  # comment marker, backslash, or stray quote.
  defp segment_gen do
    letters = StreamData.string(?a..?z, min_length: 1, max_length: 6)
    quoted_body = StreamData.string([?a..?z, ?\s, ?;], max_length: 6)

    gen all(
          head <- letters,
          mid <-
            StreamData.one_of([StreamData.constant(""), StreamData.map(quoted_body, &"'#{&1}'")]),
          tail <- letters
        ) do
      head <> mid <> tail
    end
  end

  property "joining statements with `;` round-trips back through split/1" do
    check all(statements <- StreamData.list_of(segment_gen(), min_length: 1, max_length: 5)) do
      batch = Enum.join(statements, ";")
      assert StatementSplitter.split(batch) == statements
    end
  end
end
