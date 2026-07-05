# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.PackStream.DatetimeTzTest do
  # async: false — these tests flip the global `:time_zone_database`, so they
  # must not run concurrently with anything that resolves a named zone.
  use ExUnit.Case, async: false

  alias Bolty.PackStream

  # A packed evolved (0x69) datetime-with-zone-id for "Europe/Berlin" (the exact
  # bytes the encoder produces in pack_stream_test); decoding it resolves the
  # named zone, which needs a configured `:time_zone_database`.
  @berlin_datetime <<0xB3, 0x69, 0xCA, 0x57, 0x44, 0x3A, 0x50, 0xCA, 0x27, 0x0, 0x25, 0x68, 0x8D,
                     0x45, 0x75, 0x72, 0x6F, 0x70, 0x65, 0x2F, 0x42, 0x65, 0x72, 0x6C, 0x69,
                     0x6E>>

  test "decoding a named-zone datetime with no :time_zone_database returns a clear error, not a crash" do
    previous = Calendar.get_time_zone_database()
    Calendar.put_time_zone_database(Calendar.UTCOnlyTimeZoneDatabase)

    try do
      assert {:error, %Bolty.Error{code: :time_zone_database_not_configured} = error} =
               PackStream.unpack(@berlin_datetime)

      assert Exception.message(error) =~ ":time_zone_database"
    after
      Calendar.put_time_zone_database(previous)
    end
  end

  test "with a time zone database configured it decodes to the named-zone DateTime" do
    assert {:ok, [%DateTime{time_zone: "Europe/Berlin"}]} = PackStream.unpack(@berlin_datetime)
  end
end
