# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Large.Result.Set.Test do
  use ExUnit.Case, async: true

  @moduletag :integration

  # Regression for #57: a result message larger than a single Bolt chunk
  # (> 65_535 bytes) is split by the server across multiple chunks. The reader
  # must reassemble the chunk payloads before decoding; previously it assumed
  # one chunk per message, desynced the stream, and raised in the decoder.

  @opts Bolty.TestHelper.opts()

  setup do
    {:ok, conn} = Bolty.start_link([pool_size: 1] ++ @opts)
    {:ok, conn: conn}
  end

  @tag :core
  test "reassembles a single record far larger than one chunk", %{conn: conn} do
    # A 100_000-element integer list encodes to several hundred KB in one RECORD,
    # forcing the server to split that message across multiple chunks.
    assert {:ok, response} = Bolty.query(conn, "RETURN range(1, 100000) AS nums")
    nums = List.first(response.results)["nums"]

    assert length(nums) == 100_000
    assert List.first(nums) == 1
    assert List.last(nums) == 100_000
  end

  @tag :core
  test "the connection stays usable after a large result", %{conn: conn} do
    assert {:ok, _} = Bolty.query(conn, "RETURN range(1, 100000) AS nums")

    assert {:ok, response} = Bolty.query(conn, "RETURN 7 AS n")
    assert [%{"n" => 7}] = response.results
  end
end
