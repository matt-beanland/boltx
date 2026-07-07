# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule StreamingTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Bolty.Response

  @opts Bolty.TestHelper.opts()

  setup do
    {:ok, conn} = Bolty.start_link([pool_size: 1] ++ @opts)
    {:ok, conn: conn}
  end

  @tag :core
  test "streams a large result in fetch_size batches, preserving order and count", %{conn: conn} do
    {:ok, batches} =
      Bolty.transaction(conn, fn c ->
        c
        |> Bolty.stream("UNWIND range(1, 250) AS i RETURN i", %{}, fetch_size: 100)
        |> Enum.to_list()
      end)

    # 250 records at fetch_size 100 -> three batches of 100, 100, 50.
    assert Enum.map(batches, &length(&1.results)) == [100, 100, 50]

    all = batches |> Enum.flat_map(& &1.results) |> Enum.map(& &1["i"])
    assert length(all) == 250
    assert List.first(all) == 1
    assert List.last(all) == 250
  end

  @tag :core
  test "each batch is a %Bolty.Response{}; summary lands on the final batch only", %{conn: conn} do
    {:ok, batches} =
      Bolty.transaction(conn, fn c ->
        c
        |> Bolty.stream("UNWIND range(1, 150) AS i RETURN i AS n", %{}, fetch_size: 100)
        |> Enum.to_list()
      end)

    assert Enum.all?(batches, &match?(%Response{}, &1))
    assert Enum.all?(batches, &(&1.fields == ["n"]))

    # The trailing SUCCESS (type/bookmark) arrives with the last batch, not the first.
    assert List.first(batches).type == nil
    assert List.last(batches).type != nil
  end

  @tag :core
  test "early termination stops fetching and returns the connection clean", %{conn: conn} do
    {:ok, taken} =
      Bolty.transaction(conn, fn c ->
        c
        |> Bolty.stream("UNWIND range(1, 1000) AS i RETURN i", %{}, fetch_size: 100)
        |> Stream.flat_map(& &1.results)
        |> Enum.take(250)
      end)

    assert length(taken) == 250
    assert List.last(taken)["i"] == 250

    # The remainder was DISCARDed at deallocate; the pooled connection is usable.
    assert {:ok, %Response{results: [%{"n" => 7}]}} = Bolty.query(conn, "RETURN 7 AS n")
  end

  @tag :core
  test "fetch_size defaults to 1000", %{conn: conn} do
    {:ok, batch_count} =
      Bolty.transaction(conn, fn c ->
        c
        |> Bolty.stream("UNWIND range(1, 1000) AS i RETURN i")
        |> Enum.count()
      end)

    assert batch_count == 1
  end

  @tag :core
  test "a failing streamed query raises without poisoning the connection", %{conn: conn} do
    # A stream surfaces a mid-fetch failure by raising during enumeration (the
    # Enumerable protocol has no error-tuple channel), unlike query/4's
    # {:error, _}. The raise propagates out of the transaction fun.
    assert_raise Bolty.Error, fn ->
      Bolty.transaction(conn, fn c ->
        c
        |> Bolty.stream("RETURN 1 / 0 AS boom")
        |> Enum.to_list()
      end)
    end

    # RESET recovery leaves the pooled connection usable for the next checkout.
    assert {:ok, %Response{results: [%{"n" => 7}]}} = Bolty.query(conn, "RETURN 7 AS n")
  end

  @tag :core
  test "emits :start, one :fetch per batch, and a single :stop", %{conn: conn} do
    events = [[:bolty, :stream, :start], [:bolty, :stream, :fetch], [:bolty, :stream, :stop]]
    handler = "streaming-test-#{inspect(self())}"
    me = self()

    :telemetry.attach_many(
      handler,
      events,
      fn event, measurements, metadata, _ -> send(me, {event, measurements, metadata}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    {:ok, _} =
      Bolty.transaction(conn, fn c ->
        c
        |> Bolty.stream("UNWIND range(1, 250) AS i RETURN i", %{}, fetch_size: 100)
        |> Stream.run()
      end)

    assert_receive {[:bolty, :stream, :start], %{system_time: _}, %{fetch_size: 100}}

    assert_receive {[:bolty, :stream, :fetch], %{records: 100}, %{has_more: true}}
    assert_receive {[:bolty, :stream, :fetch], %{records: 100}, %{has_more: true}}
    assert_receive {[:bolty, :stream, :fetch], %{records: 50}, %{has_more: false}}

    assert_receive {[:bolty, :stream, :stop], %{duration: _}, %{db_system: "neo4j"}}
  end
end
