# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.BoltProtocol.Message.RunMessage do
  @moduledoc false

  alias Bolty.BoltProtocol.MessageDecoder
  alias Bolty.BoltProtocol.MessageEncoder
  alias Bolty.Policy

  @signature 0x10

  def encode(bolt_version, query, parameters, extra_parameters, policy \\ %Policy{})

  def encode(bolt_version, query, parameters, extra_parameters, policy)
      when is_tuple(bolt_version) and bolt_version >= {3, 0} do
    message = [query, parameters, get_extra_parameters(extra_parameters)]
    MessageEncoder.encode(@signature, message, policy)
  end

  def encode(_, _, _, _, _) do
    MessageEncoder.unsupported_version_error(__MODULE__, "RUN")
  end

  def prepare_messages(_bolt_version, messages) do
    MessageDecoder.prepare_generic(__MODULE__, messages)
  end

  defp get_extra_parameters(extra_parameters) do
    %{
      bookmarks: Map.get(extra_parameters, :bookmarks, []),
      mode: Map.get(extra_parameters, :mode, "w"),
      db: Map.get(extra_parameters, :db, nil),
      tx_metadata: Map.get(extra_parameters, :tx_metadata, nil)
    }
  end
end
