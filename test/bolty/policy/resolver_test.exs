# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.Policy.ResolverTest do
  use ExUnit.Case, async: true

  alias Bolty.Policy
  alias Bolty.Policy.Resolver

  describe "resolve/2 datetime dimension" do
    @describetag :core

    test "Bolt 3.0 resolves to :legacy" do
      assert %Policy{datetime: :legacy} = Resolver.resolve(3.0, %{"server" => "Neo4j/3.5.0"})
    end

    test "Bolt 4.0 resolves to :legacy" do
      assert %Policy{datetime: :legacy} = Resolver.resolve(4.0, %{"server" => "Neo4j/4.4.27"})
    end

    test "Bolt 4.4 against a Neo4j 5 server resolves to :legacy (scenario 2)" do
      # Neo4j 5 explicitly supports legacy datetime structs over Bolt 4.x for
      # backward compatibility. This is the exact shape that broke issue #10
      # in bolty 0.0.9 because the packer emitted 0x69 unconditionally.
      assert %Policy{datetime: :legacy} = Resolver.resolve(4.4, %{"server" => "Neo4j/5.26.26"})
    end

    test "Bolt 5.0 resolves to :evolved" do
      assert %Policy{datetime: :evolved} = Resolver.resolve(5.0, %{"server" => "Neo4j/5.26.26"})
    end

    test "Bolt 5.4 resolves to :evolved" do
      assert %Policy{datetime: :evolved} = Resolver.resolve(5.4, %{"server" => "Neo4j/5.26.26"})
    end

    test "Memgraph masquerading as Neo4j/5.2.0 at Bolt 5.2 resolves to :evolved" do
      # If calibration later shows Memgraph needs :legacy at Bolt 5.x, add a
      # server_version branch in `put_datetime/3`.
      assert %Policy{datetime: :evolved} = Resolver.resolve(5.2, %{"server" => "Neo4j/5.2.0"})
    end

    test "missing server metadata does not crash; still decides from bolt_version" do
      assert %Policy{datetime: :legacy} = Resolver.resolve(4.4, %{})
      assert %Policy{datetime: :evolved} = Resolver.resolve(5.0, %{})
    end

    test "nil bolt_version falls through to defaults (:legacy)" do
      # Defensive — connect-time call should always pass a negotiated version,
      # but the resolver shouldn't crash if something odd gets through.
      assert %Policy{datetime: :legacy} = Resolver.resolve(nil, %{"server" => "Neo4j/5.26.26"})
    end
  end
end
