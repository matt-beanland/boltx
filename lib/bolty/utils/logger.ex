# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.Utils.Logger do
  @moduledoc false
  # Designed to log Bolt protocol message between Client and Server.
  #
  # The `from` parameter must be a atom, either `:client` or `:server`
  require Logger

  # Message fields whose values are secrets and must never reach the debug log
  # in plaintext (e.g. the LOGON `credentials`, which is the account password).
  # Mirrors the `@derive {Inspect, except: [:password]}` redaction on
  # `Bolty.Client.Config`, closing the same gap on the opt-in log path.
  @redacted_keys [:credentials]
  @redacted_placeholder "[REDACTED]"

  @doc """
  Produces a formatted Log for a message

  ## Example
      iex> Logger.log_message(:client, {:init, []})
  """
  def log_message(from, {type, data}) do
    msg_type = type |> Atom.to_string() |> String.upcase()
    do_log_message(from, fn -> "#{msg_type} ~ #{inspect(data)}" end)
  end

  @doc """
  Produces a formatted Log

  ## Example
      iex> Logger.log_message(:server, :handshake, 2)
  """
  def log_message(from, type, data) do
    if Application.get_env(:bolty, :log) do
      log_message(from, {type, redact(data)})
    end
  end

  @doc """
  Produces a formatted Log for a message
  Data will be output in hexadecimal

  ## Example
      iex> Logger.log_message(:server, :handshake, <<0x02>>)
  """
  def log_message(from, type, data, :hex) do
    if Application.get_env(:bolty, :log_hex, false) do
      msg_type = type |> Atom.to_string() |> String.upcase()

      do_log_message(from, fn ->
        "#{msg_type} ~ #{inspect(data, base: :hex, limit: :infinity)}"
      end)
    end
  end

  # Recursively replaces the value of any `@redacted_keys` field with a
  # placeholder so secrets never reach the log. Structs are left intact (they
  # don't carry auth secrets, and preserving them keeps logged query params
  # readable); only plain maps and lists are walked.
  defp redact(data) when is_list(data), do: Enum.map(data, &redact/1)

  defp redact(%_{} = struct), do: struct

  defp redact(%{} = map) do
    Map.new(map, fn
      {key, _value} when key in @redacted_keys -> {key, @redacted_placeholder}
      {key, value} -> {key, redact(value)}
    end)
  end

  defp redact(data), do: data

  defp do_log_message(from, func) when is_function(func) do
    from_txt =
      case from do
        :server -> "S"
        :client -> "C"
      end

    Logger.debug(fn -> "#{from_txt}: #{func.()}" end)
  end
end
