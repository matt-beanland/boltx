# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.BoltProtocol.Message.BeginMessage do
  @moduledoc false

  alias Bolty.BoltProtocol.MessageEncoder

  @signature 0x11

  def encode(bolt_version, extra_parameters)
      when is_tuple(bolt_version) and bolt_version >= {3, 0} do
    message = [get_extra_parameters(extra_parameters)]
    MessageEncoder.encode(@signature, message)
  end

  def encode(_, _) do
    MessageEncoder.unsupported_version_error(__MODULE__, "BEGIN")
  end

  defp get_extra_parameters(extra_parameters) do
    keys_to_extract = [:bookmarks, :mode, :db, :tx_metadata]
    Map.take(extra_parameters, keys_to_extract)
  end
end
