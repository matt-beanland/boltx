# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.Policy.ResolverTest do
  use ExUnit.Case, async: true

  alias Bolty.Policy
  alias Bolty.Policy.Resolver

  describe "resolve/2 datetime dimension" do
    @describetag :core

    test "Bolt 5.0 resolves to :evolved" do
      assert %Policy{datetime: :evolved} = Resolver.resolve(5.0, %{"server" => "Neo4j/5.26.26"})
    end

    test "Bolt 5.4 resolves to :evolved" do
      assert %Policy{datetime: :evolved} = Resolver.resolve(5.4, %{"server" => "Neo4j/5.26.26"})
    end

    test "Bolt 5.8 resolves to :evolved" do
      assert %Policy{datetime: :evolved} = Resolver.resolve(5.8, %{"server" => "Neo4j/5.26.26"})
    end

    test "Memgraph masquerading as Neo4j/5.2.0 at Bolt 5.2 resolves to :evolved" do
      # If calibration later shows Memgraph needs :legacy at Bolt 5.x, add a
      # server_version branch in `put_datetime/3`.
      assert %Policy{datetime: :evolved} = Resolver.resolve(5.2, %{"server" => "Neo4j/5.2.0"})
    end

    test "missing server metadata does not crash; still decides from bolt_version" do
      assert %Policy{datetime: :evolved} = Resolver.resolve(5.0, %{})
    end

    test "nil bolt_version falls through to Policy defaults" do
      # Defensive — connect-time call should always pass a negotiated version.
      assert %Policy{datetime: :evolved} = Resolver.resolve(nil, %{"server" => "Neo4j/5.26.26"})
    end
  end

  describe "resolve/2 notifications_field dimension" do
    @describetag :core

    test "Bolt 5.0 uses :notifications_disabled_categories" do
      assert %Policy{notifications_field: :notifications_disabled_categories} =
               Resolver.resolve(5.0, %{})
    end

    test "Bolt 5.4 uses :notifications_disabled_categories" do
      assert %Policy{notifications_field: :notifications_disabled_categories} =
               Resolver.resolve(5.4, %{})
    end

    test "Bolt 5.6 uses :notifications_disabled_classifications" do
      assert %Policy{notifications_field: :notifications_disabled_classifications} =
               Resolver.resolve(5.6, %{})
    end

    test "Bolt 5.8 uses :notifications_disabled_classifications" do
      assert %Policy{notifications_field: :notifications_disabled_classifications} =
               Resolver.resolve(5.8, %{})
    end
  end

  describe "resolve/2 gql_errors dimension" do
    @describetag :core

    test "Bolt 5.0 has gql_errors: false" do
      assert %Policy{gql_errors: false} = Resolver.resolve(5.0, %{})
    end

    test "Bolt 5.6 has gql_errors: false" do
      assert %Policy{gql_errors: false} = Resolver.resolve(5.6, %{})
    end

    test "Bolt 5.7 has gql_errors: true" do
      assert %Policy{gql_errors: true} = Resolver.resolve(5.7, %{})
    end

    test "Bolt 5.8 has gql_errors: true" do
      assert %Policy{gql_errors: true} = Resolver.resolve(5.8, %{})
    end
  end

  describe "resolve/2 vectors dimension" do
    @describetag :core

    test "Bolt 5.8 has vectors: false" do
      assert %Policy{vectors: false} = Resolver.resolve(5.8, %{})
    end

    test "Bolt 6.0 has vectors: true" do
      assert %Policy{vectors: true} = Resolver.resolve(6.0, %{})
    end
  end
end
