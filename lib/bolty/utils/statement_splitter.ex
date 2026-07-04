# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.Utils.StatementSplitter do
  @moduledoc false
  # Splits a batch of `;`-separated Cypher statements (as accepted by
  # `Bolty.query_many/4`) into individual statements, splitting only on a
  # top-level `;` — one that is NOT inside a string literal, a comment, or a
  # backtick-quoted identifier. The terminating `;` is dropped: Bolt's RUN
  # message expects a single bare statement with no terminator.
  #
  # A hand-written byte-level state machine rather than a regex: a regex cannot
  # track the string/comment/backtick context a `;` may hide inside, and there
  # is no maintained Cypher lexer to depend on. Working a byte at a time is safe
  # because every delimiter we care about (`; ' " ` / * \\ \n`) is ASCII, and an
  # ASCII byte never appears inside a multi-byte UTF-8 sequence — so segments are
  # byte-identical slices of the input, produced with `binary_part/3`.

  @doc """
  Splits `statement` on top-level `;` and returns the trimmed, non-empty
  statements. Blank and comment-only segments are dropped so they never reach
  the server (where they would error and halt the batch mid-way).
  """
  @spec split(binary) :: [binary]
  def split(statement) when is_binary(statement) do
    statement
    |> scan(statement, 0, [], :normal)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&significant?/1)
  end

  # scan(rest, seg, len, acc, state)
  #   rest — the not-yet-consumed tail
  #   seg  — the input binary as it was at the start of the current segment
  #   len  — bytes consumed into the current segment so far
  #   acc  — completed segments, in reverse order
  # A completed segment is `binary_part(seg, 0, len)`; a top-level `;` closes the
  # current segment (delimiter dropped) and opens a new one at the next byte.

  # End of input: flush whatever segment is open, in whatever state.
  defp scan(<<>>, seg, len, acc, _state),
    do: Enum.reverse([binary_part(seg, 0, len) | acc])

  # :normal — the only state where `;` splits and quotes/comments open.
  defp scan(<<";", rest::binary>>, seg, len, acc, :normal),
    do: scan(rest, rest, 0, [binary_part(seg, 0, len) | acc], :normal)

  defp scan(<<"//", rest::binary>>, seg, len, acc, :normal),
    do: scan(rest, seg, len + 2, acc, :line_comment)

  defp scan(<<"/*", rest::binary>>, seg, len, acc, :normal),
    do: scan(rest, seg, len + 2, acc, :block_comment)

  defp scan(<<"'", rest::binary>>, seg, len, acc, :normal),
    do: scan(rest, seg, len + 1, acc, :single)

  defp scan(<<"\"", rest::binary>>, seg, len, acc, :normal),
    do: scan(rest, seg, len + 1, acc, :double)

  defp scan(<<"`", rest::binary>>, seg, len, acc, :normal),
    do: scan(rest, seg, len + 1, acc, :backtick)

  defp scan(<<_c, rest::binary>>, seg, len, acc, :normal),
    do: scan(rest, seg, len + 1, acc, :normal)

  # :single / :double — backslash escapes the next byte (`\'`, `\"`, `\\`).
  defp scan(<<"\\", _c, rest::binary>>, seg, len, acc, :single),
    do: scan(rest, seg, len + 2, acc, :single)

  defp scan(<<"'", rest::binary>>, seg, len, acc, :single),
    do: scan(rest, seg, len + 1, acc, :normal)

  defp scan(<<_c, rest::binary>>, seg, len, acc, :single),
    do: scan(rest, seg, len + 1, acc, :single)

  defp scan(<<"\\", _c, rest::binary>>, seg, len, acc, :double),
    do: scan(rest, seg, len + 2, acc, :double)

  defp scan(<<"\"", rest::binary>>, seg, len, acc, :double),
    do: scan(rest, seg, len + 1, acc, :normal)

  defp scan(<<_c, rest::binary>>, seg, len, acc, :double),
    do: scan(rest, seg, len + 1, acc, :double)

  # :backtick — an identifier escapes a backtick by doubling it (``); backslash
  # is a literal, so there is no escape clause here.
  defp scan(<<"``", rest::binary>>, seg, len, acc, :backtick),
    do: scan(rest, seg, len + 2, acc, :backtick)

  defp scan(<<"`", rest::binary>>, seg, len, acc, :backtick),
    do: scan(rest, seg, len + 1, acc, :normal)

  defp scan(<<_c, rest::binary>>, seg, len, acc, :backtick),
    do: scan(rest, seg, len + 1, acc, :backtick)

  # :line_comment — runs to the newline (or EOF).
  defp scan(<<"\n", rest::binary>>, seg, len, acc, :line_comment),
    do: scan(rest, seg, len + 1, acc, :normal)

  defp scan(<<_c, rest::binary>>, seg, len, acc, :line_comment),
    do: scan(rest, seg, len + 1, acc, :line_comment)

  # :block_comment — runs to the closing `*/` (does not nest) or EOF.
  defp scan(<<"*/", rest::binary>>, seg, len, acc, :block_comment),
    do: scan(rest, seg, len + 2, acc, :normal)

  defp scan(<<_c, rest::binary>>, seg, len, acc, :block_comment),
    do: scan(rest, seg, len + 1, acc, :block_comment)

  # A segment is worth sending if it holds any non-whitespace byte outside a
  # comment. Strings/backticks/anything else count as content the moment they
  # appear; only whitespace and comment bodies do not.
  defp significant?(seg), do: significant?(seg, :code)

  defp significant?(<<>>, _state), do: false

  defp significant?(<<"//", rest::binary>>, :code), do: significant?(rest, :line_comment)
  defp significant?(<<"/*", rest::binary>>, :code), do: significant?(rest, :block_comment)

  defp significant?(<<c, rest::binary>>, :code) when c in [?\s, ?\t, ?\r, ?\n],
    do: significant?(rest, :code)

  defp significant?(<<_c, _rest::binary>>, :code), do: true

  defp significant?(<<"\n", rest::binary>>, :line_comment), do: significant?(rest, :code)
  defp significant?(<<_c, rest::binary>>, :line_comment), do: significant?(rest, :line_comment)

  defp significant?(<<"*/", rest::binary>>, :block_comment), do: significant?(rest, :code)
  defp significant?(<<_c, rest::binary>>, :block_comment), do: significant?(rest, :block_comment)
end
