# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.PolicyTest do
  use ExUnit.Case, async: true

  alias Bolty.Policy
  alias Bolty.Policy.Resolver

  describe "override/2" do
    @describetag :core

    setup do
      # What a server emulating Neo4j 2026.05 resolves to by inference.
      {:ok, inferred: Resolver.resolve({6, 0}, %{"server" => "Neo4j/2026.05.0"})}
    end

    test "no overrides leaves the inferred policy untouched", %{inferred: inferred} do
      assert {:ok, ^inferred} = Policy.override(inferred, [])
    end

    test "adds a capability the version string cannot reveal", %{inferred: inferred} do
      assert {:ok, %Policy{cypher_features: features}} =
               Policy.override(inferred, cypher_features: [:disjoint_by])

      assert MapSet.equal?(features, MapSet.new([:disjoint_by]))
    end

    test "replaces rather than merges, so a wrong inference can be withdrawn" do
      inferred = Resolver.resolve({6, 0}, %{"server" => "Neo4j/2026.06.0"})
      assert MapSet.member?(inferred.cypher_features, :vector_hfq)

      assert {:ok, %Policy{cypher_features: features}} =
               Policy.override(inferred, cypher_features: [:disjoint_by])

      refute MapSet.member?(features, :vector_hfq)
    end

    test "a non-Neo4j server can be given the Cypher flags it actually has" do
      inferred = Resolver.resolve({6, 0}, %{"server" => "SomeOtherDB/1.2.3"})
      assert %Policy{cypher_25: false, dynamic_labels: false} = inferred

      assert {:ok, %Policy{cypher_25: true, dynamic_labels: true, cypher_features: features}} =
               Policy.override(inferred,
                 cypher_25: true,
                 dynamic_labels: true,
                 cypher_features: [:disjoint_by]
               )

      assert MapSet.member?(features, :disjoint_by)
    end

    test "accepts a MapSet as readily as a list", %{inferred: inferred} do
      assert {:ok, %Policy{cypher_features: features}} =
               Policy.override(inferred, cypher_features: MapSet.new([:vector_hfq]))

      assert MapSet.equal?(features, MapSet.new([:vector_hfq]))
    end

    test "rejects wire-level dimensions — they are negotiated, not asserted", %{
      inferred: inferred
    } do
      assert {:error, %Bolty.Error{code: :invalid_capability} = error} =
               Policy.override(inferred, vectors: false)

      assert error.bolt.message =~ "cannot override [:vectors]"
    end

    test "rejects an unknown flag rather than silently ignoring it", %{inferred: inferred} do
      assert {:error, %Bolty.Error{code: :invalid_capability}} =
               Policy.override(inferred, cypher_26: true)
    end
  end
end
