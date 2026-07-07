# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.PackStream.Unpacker do
  @moduledoc false

  use Bolty.PackStream.Markers

  alias Bolty.Types.{
    TimeWithTZOffset,
    DateTimeWithTZOffset,
    Point,
    Vector,
    Relationship,
    UnboundRelationship,
    Node,
    Path
  }

  alias Bolty.TypesHelper

  # Null
  def unpack(<<@null_marker, rest::binary>>) do
    [nil | unpack(rest)]
  end

  # Boolean
  def unpack(<<@true_marker, rest::binary>>) do
    [true | unpack(rest)]
  end

  def unpack(<<@false_marker, rest::binary>>) do
    [false | unpack(rest)]
  end

  # Float
  def unpack(<<@float_marker, number::float, rest::binary>>) do
    [number | unpack(rest)]
  end

  # Strings
  def unpack(<<@tiny_bitstring_marker::4, str_length::4, rest::bytes>>) do
    decode_string(rest, str_length)
  end

  def unpack(<<@bitstring8_marker, str_length, rest::bytes>>) do
    decode_string(rest, str_length)
  end

  def unpack(<<@bitstring16_marker, str_length::16, rest::bytes>>) do
    decode_string(rest, str_length)
  end

  def unpack(<<@bitstring32_marker, str_length::32, rest::binary>>) do
    decode_string(rest, str_length)
  end

  # Bytes
  def unpack(<<@bytes8_marker, size::8, data::binary-size(size), rest::binary>>) do
    [data | unpack(rest)]
  end

  def unpack(<<@bytes16_marker, size::16, data::binary-size(size), rest::binary>>) do
    [data | unpack(rest)]
  end

  def unpack(<<@bytes32_marker, size::32, data::binary-size(size), rest::binary>>) do
    [data | unpack(rest)]
  end

  # Lists
  def unpack(<<@tiny_list_marker::4, list_size::4>> <> bin) do
    decode_list(bin, list_size)
  end

  def unpack(<<@list8_marker, list_size::8>> <> bin) do
    decode_list(bin, list_size)
  end

  def unpack(<<@list16_marker, list_size::16>> <> bin) do
    decode_list(bin, list_size)
  end

  def unpack(<<@list32_marker, list_size::32>> <> bin) do
    decode_list(bin, list_size)
  end

  # Maps
  def unpack(<<@tiny_map_marker::4, entries::4>> <> bin) do
    decode_map(bin, entries)
  end

  def unpack(<<@map8_marker, entries::8>> <> bin) do
    decode_map(bin, entries)
  end

  def unpack(<<@map16_marker, entries::16>> <> bin) do
    decode_map(bin, entries)
  end

  def unpack(<<@map32_marker, entries::32>> <> bin) do
    decode_map(bin, entries)
  end

  # Struct
  def unpack(<<@tiny_struct_marker::4, struct_size::4, sig::8>> <> struct) do
    unpack({sig, struct, struct_size})
  end

  def unpack(<<@struct8_marker, struct_size::8, sig::8>> <> struct) do
    unpack({sig, struct, struct_size})
  end

  def unpack(<<@struct16_marker, struct_size::16, sig::8>> <> struct) do
    unpack({sig, struct, struct_size})
  end

  ######### SPECIAL STRUCTS

  # Node
  def unpack({@node_marker, struct, struct_size}) do
    {structure_data, rest} = decode_struct(struct, struct_size)

    field_names = [:id, :labels, :properties, :element_id]
    node_data = Enum.zip([field_names, structure_data])
    node = struct(Node, node_data)

    [node | rest]
  end

  # Relationship
  def unpack({@relationship_marker, struct, struct_size}) do
    {structure_data, rest} =
      decode_struct(struct, struct_size)

    field_names = [
      :id,
      :start,
      :end,
      :type,
      :properties,
      :element_id,
      :start_node_element_id,
      :end_node_element_id
    ]

    relationship_data = Enum.zip([field_names, structure_data])
    relationship = struct(Relationship, relationship_data)

    [relationship | rest]
  end

  # UnboundedRelationship
  def unpack({@unbounded_relationship_marker, struct, struct_size}) do
    {structure_data, rest} = decode_struct(struct, struct_size)

    field_names = [:id, :type, :properties, :element_id]
    unbounded_relationship_data = Enum.zip([field_names, structure_data])
    unbounded_relationship = struct(UnboundRelationship, unbounded_relationship_data)

    [unbounded_relationship | rest]
  end

  # Path
  def unpack({@path_marker, struct, struct_size}) do
    {structure_data, rest} =
      decode_struct(struct, struct_size)

    field_names = [:nodes, :relationships, :sequence]
    path_data = Enum.zip([field_names, structure_data])
    path = struct(Path, path_data)

    [path | rest]
  end

  # Manage the end of data
  def unpack(<<>>), do: []

  # Integer
  def unpack(<<@int8_marker, int::signed-integer, rest::binary>>) do
    [int | unpack(rest)]
  end

  def unpack(<<@int16_marker, int::signed-integer-16, rest::binary>>) do
    [int | unpack(rest)]
  end

  def unpack(<<@int32_marker, int::signed-integer-32, rest::binary>>) do
    [int | unpack(rest)]
  end

  def unpack(<<@int64_marker, int::signed-integer-64, rest::binary>>) do
    [int | unpack(rest)]
  end

  # Tiny integer: a single byte holding -16..127 (markers 0xF0..0xFF and
  # 0x00..0x7F). Bounded explicitly so an unknown/reserved marker byte can't be
  # silently misread as a tiny int.
  def unpack(<<int::signed-integer, rest::binary>>) when int in -16..127 do
    [int | unpack(rest)]
  end

  # Unknown / reserved PackStream marker. Fail loudly rather than decode a corrupt
  # or malicious byte as data. Thrown (not raised) so PackStream.unpack/1 surfaces
  # it as {:error, %Bolty.Error{}} via its try/catch.
  def unpack(<<marker, _rest::binary>>) do
    throw(
      Bolty.Error.wrap(__MODULE__, %{
        code: :unknown_marker,
        message: "unknown PackStream marker 0x" <> Integer.to_string(marker, 16)
      })
    )
  end

  # Local Date
  def unpack({@date_signature, struct, @date_struct_size}) do
    {[date], rest} = decode_struct(struct, @date_struct_size)
    [Date.add(~D[1970-01-01], date) | rest]
  end

  # Local Time
  def unpack({@local_time_signature, struct, @local_time_struct_size}) do
    {[time], rest} = decode_struct(struct, @local_time_struct_size)

    [Time.add(~T[00:00:00.000000], time, :nanosecond) | rest]
  end

  # Local DateTime
  def unpack({@local_datetime_signature, struct, @local_datetime_struct_size}) do
    {[seconds, nanoseconds], rest} =
      decode_struct(struct, @local_datetime_struct_size)

    ndt =
      NaiveDateTime.add(
        ~N[1970-01-01 00:00:00.000000000],
        seconds * 1_000_000_000 + nanoseconds,
        :nanosecond
      )

    [ndt | rest]
  end

  # Time with Zone Offset
  def unpack({@time_with_tz_signature, struct, @time_with_tz_struct_size}) do
    {[time, offset], rest} = decode_struct(struct, @time_with_tz_struct_size)

    t = TimeWithTZOffset.create(Time.add(~T[00:00:00.000000], time, :nanosecond), offset)
    [t | rest]
  end

  # Datetime with zone Id
  def unpack({@datetime_with_zone_id_signature, struct, @datetime_with_zone_id_struct_size}) do
    {[seconds, nanoseconds, zone_id], rest} =
      decode_struct(struct, @datetime_with_zone_id_struct_size)

    {:ok, instant} = DateTime.from_unix(seconds * 1_000_000_000 + nanoseconds, :nanosecond)

    # Resolving the named zone needs a configured Elixir `:time_zone_database`.
    # Throw a clear %Bolty.Error{} (which PackStream.unpack/1 surfaces as
    # {:error, _}) rather than let a MatchError escape when a consumer has not
    # configured one — the common case being a UTC-only default database.
    datetime =
      case DateTime.shift_zone(instant, zone_id) do
        {:ok, datetime} -> datetime
        {:error, reason} -> throw(zone_resolution_error(zone_id, reason))
      end

    [datetime | rest]
  end

  # Datetime with zone offset
  def unpack(
        {@datetime_with_zone_offset_signature, struct, @datetime_with_zone_offset_struct_size}
      ) do
    {[seconds, nanoseconds, zone_offset], rest} =
      decode_struct(struct, @datetime_with_zone_offset_struct_size)

    naive_dt =
      NaiveDateTime.add(
        ~N[1970-01-01 00:00:00.000000],
        (seconds + zone_offset) * 1_000_000_000 + nanoseconds,
        :nanosecond
      )

    dt = DateTimeWithTZOffset.create(naive_dt, zone_offset)
    [dt | rest]
  end

  # Duration
  def unpack({@duration_signature, struct, @duration_struct_size}) do
    {[months, days, seconds, nanoseconds], rest} =
      decode_struct(struct, @duration_struct_size)

    duration = TypesHelper.create_duration(months, days, seconds, nanoseconds)
    [duration | rest]
  end

  # Point2D
  def unpack({@point2d_signature, struct, @point2d_struct_size}) do
    {[srid, x, y], rest} = decode_struct(struct, @point2d_struct_size)
    point = Point.create(srid, x, y)

    [point | rest]
  end

  # Point3D
  def unpack({@point3d_signature, struct, @point3d_struct_size}) do
    {[srid, x, y, z], rest} = decode_struct(struct, @point3d_struct_size)
    point = Point.create(srid, x, y, z)

    [point | rest]
  end

  # Vector (Bolt 6.0+)
  def unpack({@vector_signature, struct, @vector_struct_size}) do
    {[type_marker, data], rest} = decode_struct(struct, @vector_struct_size)
    [decode_vector(type_marker, data) | rest]
  end

  # Unknown struct signature. Fail loudly (thrown, so PackStream.unpack/1 returns
  # {:error, %Bolty.Error{}}) rather than crash with a FunctionClauseError on a
  # corrupt or unsupported server structure.
  def unpack({signature, _struct, _struct_size}) do
    throw(
      Bolty.Error.wrap(__MODULE__, %{
        code: :unknown_marker,
        message: "unknown PackStream struct signature 0x" <> Integer.to_string(signature, 16)
      })
    )
  end

  # Private

  # A failure to resolve a datetime's named zone into a clear %Bolty.Error{}.
  # The UTC-only default database is the common footgun: the consumer never
  # configured a real `:time_zone_database`.
  defp zone_resolution_error(zone_id, :utc_only_time_zone_database) do
    Bolty.Error.wrap(__MODULE__, %{
      code: :time_zone_database_not_configured,
      message:
        "received a datetime in zone #{inspect(zone_id)} but no Elixir " <>
          ":time_zone_database is configured; set one (e.g. tz or tzdata) to " <>
          "decode named-zone datetimes"
    })
  end

  defp zone_resolution_error(zone_id, reason) do
    Bolty.Error.wrap(__MODULE__, %{
      code: :time_zone_resolution_failed,
      message: "could not resolve datetime zone #{inspect(zone_id)}: #{inspect(reason)}"
    })
  end

  @spec decode_string(binary(), integer()) :: list()
  defp decode_string(bytes, str_length) do
    <<string::binary-size(^str_length), rest::binary>> = bytes

    [string | unpack(rest)]
  end

  @spec decode_list(binary(), integer()) :: list()
  defp decode_list(list, list_size) do
    {list, rest} = list |> unpack() |> Enum.split(list_size)
    [list | rest]
  end

  @spec decode_map(binary(), integer()) :: list()
  defp decode_map(map, entries) do
    {map, rest} = map |> unpack() |> Enum.split(entries * 2)

    [to_map(map) | rest]
  end

  @spec decode_vector(binary(), binary()) :: Vector.t()
  defp decode_vector(<<@vector_float32_marker>>, data) do
    values = for <<v::big-float-size(32) <- data>>, do: v
    %Vector{type: :float32, data: values}
  end

  defp decode_vector(<<@vector_float64_marker>>, data) do
    values = for <<v::big-float-size(64) <- data>>, do: v
    %Vector{type: :float64, data: values}
  end

  @spec decode_struct(binary(), integer()) :: {list(), list()}
  def decode_struct(struct, struct_size) do
    struct
    |> unpack()
    |> Enum.split(struct_size)
  end

  @spec to_map(list()) :: map()
  defp to_map(map) do
    map
    |> Enum.chunk_every(2)
    |> Enum.map(&List.to_tuple/1)
    |> Map.new()
  end
end
