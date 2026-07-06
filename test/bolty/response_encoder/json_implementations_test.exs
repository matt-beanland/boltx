# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.JsonImplementationsTest do
  use ExUnit.Case, async: true

  @moduletag :core

  alias Bolty.Types.{
    DateTimeWithTZOffset,
    TimeWithTZOffset,
    Point,
    Node,
    Relationship,
    UnboundRelationship,
    Path
  }

  alias Bolty.ResponseEncoder

  defmodule TestStruct do
    defstruct [:id, :name]
  end

  test "JSON.encode!/1 on a Bolty struct matches ResponseEncoder.encode!/2" do
    # Both paths run the same `Bolty.ResponseEncoder.Json` jsonable conversion —
    # the JSON.Encoder impl (direct `JSON.encode!(struct)`) and the wrapper
    # (`ResponseEncoder.encode!/2`) — so they must produce identical output.
    assert JSON.encode!(fixture()) == ResponseEncoder.encode!(fixture(), :json)
  end

  test "a Bolty struct encodes to JSON that decodes back to the expected structure" do
    decoded = JSON.decode!(JSON.encode!(fixture()))

    assert %{"nodes" => [alice, bob], "relationships" => [knows, likes], "sequence" => [1, 1]} =
             decoded

    # Bolt types normalised to jsonable values:
    assert alice["id"] == 56
    assert alice["properties"]["name"] == "Alice"
    assert alice["properties"]["bolty"] == true
    # Duration -> ISO-8601 string
    assert alice["properties"]["duration"] == "P1Y12MT54M65S"
    # Point -> map
    assert alice["properties"]["geoloc"]["crs"] == "wgs-84-3d"
    assert alice["properties"]["geoloc"]["height"] == 50.0

    # DateTimeWithTZOffset -> ISO-8601 string; a plain (non-Bolty) struct falls
    # back to a map via the Json Any implementation.
    assert bob["properties"]["created"] == "2019-03-05T12:34:56+01:00"
    assert bob["properties"]["user_strut"] == %{"id" => 43, "name" => "Test"}

    # TimeWithTZOffset -> ISO-8601 string; deprecated integer ids preserved.
    assert knows["type"] == "KNOWS"
    assert knows["properties"]["creation_time"] == "12:34:56+02:00"
    assert knows["start"] == nil
    assert likes["type"] == "LIKES"
    assert likes["start"] == 56
    assert likes["end"] == 57
  end

  defp fixture() do
    %Path{
      nodes: [
        %Node{
          id: 56,
          labels: [],
          properties: %{
            "bolty" => true,
            "name" => "Alice",
            geoloc: Point.create(:wgs_84, 45.006, 40.32332, 50),
            duration: %Duration{
              day: 0,
              hour: 0,
              minute: 54,
              month: 12,
              microsecond: {0, 0},
              second: 65,
              week: 0,
              year: 1
            }
          }
        },
        %Node{
          id: 57,
          labels: [],
          properties: %{
            "bolty" => true,
            "name" => "Bob",
            created: DateTimeWithTZOffset.create(~N[2019-03-05 12:34:56], 3600),
            user_strut: %TestStruct{id: 43, name: "Test"}
          }
        }
      ],
      relationships: [
        %UnboundRelationship{
          id: 58,
          properties: %{
            creation_time: TimeWithTZOffset.create(~T[12:34:56], 7200)
          },
          type: "KNOWS"
        },
        %Relationship{
          end: 57,
          id: 58,
          properties: %{},
          start: 56,
          type: "LIKES"
        }
      ],
      sequence: [1, 1]
    }
  end
end
