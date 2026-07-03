# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.TimeoutTest do
  @moduledoc """
  Per-query / per-read timeouts (#74): the `:recv_timeout` option, its default,
  per-query override, and the disconnect-on-timeout behaviour. The timeout path
  is driven with a socket double so it is deterministic and needs no server.
  """
  use ExUnit.Case, async: true

  alias Bolty.Client
  alias Bolty.Client.Config

  # A socket double whose `recv/3` always reports a socket timeout, recording the
  # timeout value it was called with so we can assert what got threaded through.
  defmodule TimingOutSock do
    @moduledoc false
    def start, do: Agent.start_link(fn -> :never_called end)
    def send(_sock, _data), do: :ok

    def recv(agent, _length, timeout) do
      Agent.update(agent, fn _ -> timeout end)
      {:error, :timeout}
    end

    def last_timeout(agent), do: Agent.get(agent, & &1)
  end

  defp client(agent, recv_timeout) do
    %Client{
      sock: {TimingOutSock, agent},
      bolt_version: 5.0,
      recv_timeout: recv_timeout,
      policy: Bolty.Policy.Resolver.resolve(5.0, %{})
    }
  end

  defp exec(client, opts) do
    state = %Bolty.Connection{client: client, in_transaction: false}
    query = %Bolty.Query{statement: "RETURN 1", extra: %{}}
    Bolty.Connection.handle_execute(query, %{}, opts, state)
  end

  describe "Config" do
    @base [auth: [username: "neo4j", password: "pw"]]

    test "recv_timeout defaults to 15_000" do
      assert {:ok, %Config{recv_timeout: 15_000}} = Config.new(@base)
    end

    test "recv_timeout is taken from the :recv_timeout option" do
      assert {:ok, %Config{recv_timeout: 3_000}} = Config.new([recv_timeout: 3_000] ++ @base)

      assert {:ok, %Config{recv_timeout: :infinity}} =
               Config.new([recv_timeout: :infinity] ++ @base)
    end
  end

  describe "timeout handling" do
    test "a read timeout disconnects with %Bolty.Error{code: :timeout}" do
      {:ok, agent} = TimingOutSock.start()

      assert {:disconnect, %Bolty.Error{code: :timeout}, _state} =
               exec(client(agent, 5_000), [])
    end

    test "the connection's recv_timeout is used by default" do
      {:ok, agent} = TimingOutSock.start()

      exec(client(agent, 5_000), [])

      assert TimingOutSock.last_timeout(agent) == 5_000
    end

    test "a per-query :recv_timeout overrides the connection default" do
      {:ok, agent} = TimingOutSock.start()

      exec(client(agent, 5_000), recv_timeout: 250)

      assert TimingOutSock.last_timeout(agent) == 250
    end
  end

  describe "against a live server" do
    @describetag :integration

    @tag :core
    test "connect stores the configured recv_timeout on the client" do
      opts = [recv_timeout: 8_000] ++ Bolty.TestHelper.opts()
      assert {:ok, client} = Client.connect(opts)
      assert client.recv_timeout == 8_000
      Client.disconnect(client)
    end

    @tag :core
    test "a query with a generous per-query recv_timeout still succeeds" do
      {:ok, conn} = Bolty.start_link([pool_size: 1] ++ Bolty.TestHelper.opts())
      assert {:ok, _} = Bolty.query(conn, "RETURN 1 AS n", %{}, recv_timeout: 30_000)
    end
  end
end
