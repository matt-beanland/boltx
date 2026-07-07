# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.ClientHandshakeTest do
  use ExUnit.Case, async: true

  # Regression coverage for #106: a server that misbehaves during the
  # handshake (closes early, or replies with something that isn't a
  # well-formed <<0, 0, minor, major>> version response) must surface as a
  # clean %Bolty.Error{}, not crash the connect attempt with a raw
  # FunctionClauseError. No live Neo4j needed — a bare TCP stub is enough to
  # exercise the handshake decode path, so this runs under plain `mix test`.

  alias Bolty.Client

  defp start_stub_server(handler) do
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listen_socket)

    {:ok, _pid} =
      Task.start_link(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)
        handler.(socket)
      end)

    port
  end

  defp connect_opts(port) do
    [
      hostname: "127.0.0.1",
      port: port,
      scheme: "bolt",
      auth: [username: "neo4j", password: "password"],
      connect_timeout: 1_000
    ]
  end

  test "server closing the connection mid-handshake returns a clean %Bolty.Error{}" do
    port =
      start_stub_server(fn socket ->
        :gen_tcp.close(socket)
      end)

    assert {:error, %Bolty.Error{}} = Client.connect(connect_opts(port))
  end

  test "server replying with a malformed handshake response returns a clean %Bolty.Error{}" do
    port =
      start_stub_server(fn socket ->
        # Drain whatever the client sent, then reply with bytes that don't
        # match the <<0, 0, minor, major>> version-response shape at all.
        :gen_tcp.recv(socket, 0, 1_000)
        :gen_tcp.send(socket, <<9, 9, 9, 9>>)
      end)

    assert {:error, %Bolty.Error{}} = Client.connect(connect_opts(port))
  end
end
