# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.TypesTest do
  use ExUnit.Case, async: true

  alias Bolty.Types.{DateTimeWithTZOffset, TimeWithTZOffset, Point}
  alias Bolty.Types.{Node, Path, Relationship, UnboundRelationship}

  describe "TimeWithTZOffset struct:" do
    test "create/2" do
      expected = %TimeWithTZOffset{time: ~T[20:00:43], timezone_offset: 3600}
      assert ^expected = TimeWithTZOffset.create(~T[20:00:43], 3600)
    end

    test "format_param/1 successful with valid data" do
      t = %TimeWithTZOffset{time: ~T[23:00:07], timezone_offset: 3600}
      assert {:ok, "23:00:07+01:00"} = TimeWithTZOffset.format_param(t)
    end

    test "format_param/1 fails for invalid data" do
      t = %TimeWithTZOffset{time: ~T[23:00:07], timezone_offset: 3600.543}
      assert {:error, ^t} = TimeWithTZOffset.format_param(t)
    end
  end

  describe "DateTimeWithTZOffset struct:" do
    test "create/2" do
      expected = %DateTimeWithTZOffset{
        naive_datetime: ~N[2000-01-01 23:00:07],
        timezone_offset: 3600
      }

      assert ^expected = DateTimeWithTZOffset.create(~N[2000-01-01 23:00:07], 3600)
    end

    test "format_param/1 successful with valid data" do
      t = %DateTimeWithTZOffset{
        naive_datetime: ~N[2000-01-01 23:00:07],
        timezone_offset: 3600
      }

      assert {:ok, "2000-01-01T23:00:07+01:00"} = DateTimeWithTZOffset.format_param(t)
    end

    test "format_param/2 fails for invalid data" do
      # timezone_offset can't be a float
      t = %DateTimeWithTZOffset{
        naive_datetime: ~N[2000-01-01 23:00:07],
        timezone_offset: 3600.43
      }

      assert {:error, ^t} = DateTimeWithTZOffset.format_param(t)
    end
  end

  describe "Point struct:" do
    test "create/3 succesfully creates a CARTESIAN point 2D" do
      expected = %Point{
        crs: "cartesian",
        srid: 7203,
        latitude: nil,
        longitude: nil,
        height: nil,
        x: 10.0,
        y: 20.0,
        z: nil
      }

      assert expected == Point.create(:cartesian, 10, 20.0)
    end

    test "create/3 succesfully creates a GEOGRAPHIC point 2D" do
      expected = %Point{
        crs: "wgs-84",
        srid: 4326,
        latitude: 20.0,
        longitude: 10.0,
        height: nil,
        x: 10.0,
        y: 20.0,
        z: nil
      }

      assert expected == Point.create(:wgs_84, 10, 20.0)
    end

    test "create/4 succesfully creates a CARTESIAN point 3D" do
      expected = %Point{
        crs: "cartesian-3d",
        srid: 9157,
        latitude: nil,
        longitude: nil,
        height: nil,
        x: 10.0,
        y: 20.0,
        z: 25.43
      }

      assert expected == Point.create(:cartesian, 10, 20.0, 25.43)
    end

    test "create/4 succesfully creates a GEOGRAPHIC point 3D" do
      expected = %Point{
        crs: "wgs-84-3d",
        srid: 4979,
        latitude: 20.0,
        longitude: 10.0,
        height: 25.43,
        x: 10.0,
        y: 20.0,
        z: 25.43
      }

      assert expected == Point.create(:wgs_84, 10, 20.0, 25.43)
    end

    test "format_param/1 successful with valid param" do
      point = Point.create(:wgs_84, 10, 20.0, 25.43)

      expected = %{
        crs: "wgs-84-3d",
        height: 25.43,
        latitude: 20.0,
        longitude: 10.0,
        x: 10.0,
        y: 20.0,
        z: 25.43
      }

      assert {:ok, expected} == Point.format_param(point)
    end

    test "format_param/2 fails for invalid param" do
      point = %Point{
        crs: "wgs-84-3d",
        srid: 4979,
        latitude: 20.0,
        longitude: 10.0,
        height: 25.43,
        x: 10.0,
        y: 20.0,
        z: "invalid"
      }

      assert {:error, ^point} = Point.format_param(point)
    end
  end

  describe "Path.graph/1 (#55)" do
    test "returns bound Relationship structs that carry their start/end endpoints" do
      nodes = [
        %Node{id: 100, labels: ["A"], properties: %{}},
        %Node{id: 200, labels: ["B"], properties: %{}},
        %Node{id: 300, labels: ["C"], properties: %{}}
      ]

      rels = [
        %UnboundRelationship{id: 10, type: "KNOWS", properties: %{}},
        %UnboundRelationship{id: 20, type: "KNOWS", properties: %{}}
      ]

      # A -> B -> C, both relationships traversed forward.
      path = %Path{nodes: nodes, relationships: rels, sequence: [1, 1, 2, 2]}

      assert [
               %Node{id: 100},
               %Relationship{id: 10, type: "KNOWS", start: 100, end: 200},
               %Node{id: 200},
               %Relationship{id: 20, type: "KNOWS", start: 200, end: 300},
               %Node{id: 300}
             ] = Path.graph(path)
    end

    test "encodes relationship direction independently of traversal (reverse edge)" do
      nodes = [
        %Node{id: 100, labels: ["A"], properties: %{}},
        %Node{id: 200, labels: ["B"], properties: %{}}
      ]

      rels = [%UnboundRelationship{id: 10, type: "KNOWS", properties: %{}}]

      # Walk A -> B across a relationship pointing B -> A; Neo4j encodes the
      # reverse step as -1, surfaced as 255 by the unpacker. The relationship's
      # own direction (start 200, end 100) is preserved, opposite the walk.
      path = %Path{nodes: nodes, relationships: rels, sequence: [255, 1]}

      assert [
               %Node{id: 100},
               %Relationship{id: 10, start: 200, end: 100},
               %Node{id: 200}
             ] = Path.graph(path)
    end
  end
end
