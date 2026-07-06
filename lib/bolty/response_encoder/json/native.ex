# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.ResponseEncoder.Json.Native do
  @moduledoc """
  `JSON.Encoder` implementations for `Bolty.Types.*`, using Elixir's built-in
  `JSON` (Elixir 1.18+).

  These let a query result — or any value containing Bolty types — be handed
  straight to `JSON.encode!/1`:

  ```
  {:ok, conn} = Bolty.start_link(uri: "bolt://localhost:7687", auth: [username: "neo4j", password: "..."])
  {:ok, res} = Bolty.query(conn, "MATCH (t:TestNode) RETURN t")
  JSON.encode!(res)
  ```

  Each implementation first runs the value through the `Bolty.ResponseEncoder.Json`
  protocol (which normalises a Bolty type into a plain jsonable value), then hands
  the result to the matching built-in `JSON.Encoder`. Override the jsonable step by
  providing your own `Bolty.ResponseEncoder.Json` implementation.
  """
  alias Bolty.Types
  alias Bolty.ResponseEncoder.Json

  defimpl JSON.Encoder, for: [Types.Node, Types.Relationship, Types.Path, Types.Point] do
    def encode(data, encoder) do
      data
      |> Json.encode()
      |> JSON.Encoder.Map.encode(encoder)
    end
  end

  # `Duration` is intentionally absent: Elixir 1.18+ ships a built-in
  # `JSON.Encoder.Duration`, so a raw `JSON.encode!(%Duration{})` uses that
  # standard ISO-8601 output. bolty's own encode paths (`ResponseEncoder`, and
  # the struct impls above) run every value through `Bolty.ResponseEncoder.Json`
  # first, which renders `Duration` in Neo4j's format via `format_duration/1`, so
  # a Duration nested in a query result is still emitted the Neo4j way.
  defimpl JSON.Encoder, for: [Types.DateTimeWithTZOffset, Types.TimeWithTZOffset] do
    def encode(data, encoder) do
      data
      |> Json.encode()
      |> JSON.Encoder.BitString.encode(encoder)
    end
  end
end
