# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.ConnectionResetRescueTest do
  use ExUnit.Case, async: true

  # Regression for #58: a statement FAILURE triggers a recovery RESET. If that
  # RESET *raises* (rather than returning {:error, …}) the connection is unusable,
  # but the caller must still be disconnected with the ORIGINAL query error — a
  # failed RESET must never mask what actually went wrong.

  # A socket double: `recv/3` replays a scripted list of binaries (one per call),
  # `send/2` is a no-op. Lets us drive the client through an exact server-response
  # sequence without a real connection.
  defmodule ScriptedSock do
    @moduledoc false
    def start(frames), do: Agent.start_link(fn -> frames end)
    def send(_sock, _data), do: :ok

    def recv(agent, _length, _timeout) do
      {:ok, Agent.get_and_update(agent, fn [frame | rest] -> {frame, rest} end)}
    end
  end

  @tag :core
  test "a RESET that raises disconnects with the original error, not the reset failure" do
    # Wire framing is [uint16 len][payload] chunks terminated by 0x0000.
    frames = [
      # RUN response: FAILURE carrying %{"code" => "X"} (the original error).
      <<0, 10>>,
      <<177, 127, 161, 132, 99, 111, 100, 101, 129, 88>>,
      <<0, 0>>,
      # RESET response: an undecodable body, so MessageDecoder.decode/1 raises
      # mid-recovery — exercising the rescue added for #58.
      <<0, 1>>,
      <<0>>,
      <<0, 0>>
    ]

    {:ok, agent} = ScriptedSock.start(frames)

    client = %Bolty.Client{
      sock: {ScriptedSock, agent},
      bolt_version: {5, 0},
      policy: Bolty.Policy.Resolver.resolve({5, 0}, %{})
    }

    state = %Bolty.Connection{client: client, in_transaction: false}
    query = %Bolty.Query{statement: "RETURN 1", extra: %{}}

    result = Bolty.Connection.handle_execute(query, %{}, [], state)

    # Disconnect (the connection is unusable), and the surfaced error is the
    # original RUN failure (bolt.code "X") — not the RESET's raised exception.
    assert {:disconnect, %Bolty.Error{bolt: %{code: "X"}}, _state} = result
  end
end
