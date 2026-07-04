# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.Policy.ResolverTest do
  use ExUnit.Case, async: true

  alias Bolty.Policy
  alias Bolty.Policy.Resolver

  describe "resolve/2 datetime dimension" do
    @describetag :core

    test "Bolt 5.0 resolves to :evolved" do
      assert %Policy{datetime: :evolved} =
               Resolver.resolve({5, 0}, %{"server" => "Neo4j/5.26.27"})
    end

    test "Bolt 5.4 resolves to :evolved" do
      assert %Policy{datetime: :evolved} =
               Resolver.resolve({5, 4}, %{"server" => "Neo4j/5.26.27"})
    end

    test "Bolt 5.8 resolves to :evolved" do
      assert %Policy{datetime: :evolved} =
               Resolver.resolve({5, 8}, %{"server" => "Neo4j/5.26.27"})
    end

    test "missing server metadata does not crash; still decides from bolt_version" do
      assert %Policy{datetime: :evolved} = Resolver.resolve({5, 0}, %{})
    end

    test "nil bolt_version falls through to Policy defaults" do
      # Defensive — connect-time call should always pass a negotiated version.
      assert %Policy{datetime: :evolved} = Resolver.resolve(nil, %{"server" => "Neo4j/5.26.27"})
    end
  end

  describe "resolve/2 notifications_field dimension" do
    @describetag :core

    test "Bolt 5.0 uses :notifications_disabled_categories" do
      assert %Policy{notifications_field: :notifications_disabled_categories} =
               Resolver.resolve({5, 0}, %{})
    end

    test "Bolt 5.4 uses :notifications_disabled_categories" do
      assert %Policy{notifications_field: :notifications_disabled_categories} =
               Resolver.resolve({5, 4}, %{})
    end

    test "Bolt 5.6 uses :notifications_disabled_classifications" do
      assert %Policy{notifications_field: :notifications_disabled_classifications} =
               Resolver.resolve({5, 6}, %{})
    end

    test "Bolt 5.8 uses :notifications_disabled_classifications" do
      assert %Policy{notifications_field: :notifications_disabled_classifications} =
               Resolver.resolve({5, 8}, %{})
    end
  end

  describe "resolve/2 gql_errors dimension" do
    @describetag :core

    test "Bolt 5.0 has gql_errors: false" do
      assert %Policy{gql_errors: false} = Resolver.resolve({5, 0}, %{})
    end

    test "Bolt 5.6 has gql_errors: false" do
      assert %Policy{gql_errors: false} = Resolver.resolve({5, 6}, %{})
    end

    test "Bolt 5.7 has gql_errors: true" do
      assert %Policy{gql_errors: true} = Resolver.resolve({5, 7}, %{})
    end

    test "Bolt 5.8 has gql_errors: true" do
      assert %Policy{gql_errors: true} = Resolver.resolve({5, 8}, %{})
    end
  end

  describe "resolve/2 vectors dimension" do
    @describetag :core

    test "Bolt 5.8 has vectors: false" do
      assert %Policy{vectors: false} = Resolver.resolve({5, 8}, %{})
    end

    test "Bolt 6.0 has vectors: true" do
      assert %Policy{vectors: true} = Resolver.resolve({6, 0}, %{})
    end
  end

  describe "resolve/2 cypher_5 dimension" do
    @describetag :core

    test "Bolt 5.0 has cypher_5: true" do
      assert %Policy{cypher_5: true} = Resolver.resolve({5, 0}, %{"server" => "Neo4j/5.26.27"})
    end

    test "Bolt 6.0 has cypher_5: true" do
      assert %Policy{cypher_5: true} = Resolver.resolve({6, 0}, %{"server" => "Neo4j/2026.05.0"})
    end

    test "nil bolt_version falls through to cypher_5: false" do
      assert %Policy{cypher_5: false} = Resolver.resolve(nil, %{"server" => "Neo4j/5.26.27"})
    end
  end

  describe "resolve/2 cypher_25 dimension" do
    @describetag :core

    test "calendar server >= 2025.06 has cypher_25: true" do
      assert %Policy{cypher_25: true} = Resolver.resolve({5, 8}, %{"server" => "Neo4j/2025.06.0"})
    end

    test "calendar server < 2025.06 has cypher_25: false" do
      assert %Policy{cypher_25: false} =
               Resolver.resolve({5, 8}, %{"server" => "Neo4j/2025.05.0"})
    end

    test "semver 5.26.x server has cypher_25: false" do
      assert %Policy{cypher_25: false} = Resolver.resolve({5, 8}, %{"server" => "Neo4j/5.26.27"})
    end

    test "missing server metadata has cypher_25: false" do
      assert %Policy{cypher_25: false} = Resolver.resolve({5, 8}, %{})
    end
  end

  describe "resolve/2 dynamic_labels dimension" do
    @describetag :core

    test "semver 5.26.x server has dynamic_labels: true, cypher_25: false" do
      assert %Policy{dynamic_labels: true, cypher_25: false} =
               Resolver.resolve({5, 8}, %{"server" => "Neo4j/5.26.27"})
    end

    test "calendar server >= 2025.06 has dynamic_labels and cypher_25: true" do
      assert %Policy{dynamic_labels: true, cypher_25: true} =
               Resolver.resolve({5, 8}, %{"server" => "Neo4j/2025.06.0"})
    end

    test "calendar server < 2025.06 still has dynamic_labels: true, cypher_25: false" do
      assert %Policy{dynamic_labels: true, cypher_25: false} =
               Resolver.resolve({5, 8}, %{"server" => "Neo4j/2025.05.0"})
    end

    test "pre-5.26 semver server has dynamic_labels: false" do
      assert %Policy{dynamic_labels: false} =
               Resolver.resolve({5, 8}, %{"server" => "Neo4j/5.25.1"})
    end

    test "missing server metadata has dynamic_labels: false" do
      assert %Policy{dynamic_labels: false} = Resolver.resolve({5, 8}, %{})
    end
  end
end
