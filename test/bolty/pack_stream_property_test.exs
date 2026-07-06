# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.PackStreamPropertyTest do
  @moduledoc """
  StreamData round-trip properties for the PackStream codec: `unpack(pack(x))`
  must return `x` for every representable value, and the size-marker boundaries
  (tiny/8/16/32) must be crossed correctly. Pure unit tests — no server.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Bolty.PackStream

  # Bolt integers are 64-bit signed.
  @int64_min -0x8000000000000000
  @int64_max 0x7FFFFFFFFFFFFFFF

  # Sizes either side of every String/List/Dictionary length-marker boundary:
  # tiny (<=15) -> 8-bit (<=255) -> 16-bit (<=65_535) -> 32-bit.
  @boundaries [15, 16, 255, 256, 65_535, 65_536]

  defp roundtrip(term), do: PackStream.unpack!(PackStream.pack!(term))

  # A Bolt-representable scalar. Map keys are always strings on the wire, so the
  # collection generators below key maps with strings to keep the round-trip
  # exact (an atom key would come back as a binary).
  defp scalar do
    StreamData.one_of([
      StreamData.constant(nil),
      StreamData.boolean(),
      StreamData.integer(@int64_min..@int64_max),
      StreamData.float(),
      StreamData.string(:utf8)
    ])
  end

  defp packable do
    StreamData.tree(scalar(), fn child ->
      StreamData.one_of([
        StreamData.list_of(child, max_length: 8),
        StreamData.map_of(StreamData.string(:utf8), child, max_length: 8)
      ])
    end)
  end

  property "unpack(pack(x)) == x for scalars and nested collections" do
    check all(term <- packable()) do
      assert roundtrip(term) == [term]
    end
  end

  property "unpack(pack(i)) == i across the full 64-bit integer range" do
    check all(i <- StreamData.integer(@int64_min..@int64_max)) do
      assert roundtrip(i) == [i]
    end
  end

  describe "size-marker boundaries" do
    for size <- @boundaries do
      @size size

      test "string of length #{@size} round-trips" do
        string = String.duplicate("a", @size)
        assert roundtrip(string) == [string]
      end

      test "list of length #{@size} round-trips" do
        list = List.duplicate(1, @size)
        assert roundtrip(list) == [list]
      end

      test "map of size #{@size} round-trips" do
        map = Map.new(1..@size, fn i -> {Integer.to_string(i), i} end)
        assert roundtrip(map) == [map]
      end
    end
  end
end
