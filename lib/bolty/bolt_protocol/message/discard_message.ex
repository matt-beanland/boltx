# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.BoltProtocol.Message.DiscardMessage do
  @moduledoc false

  alias Bolty.BoltProtocol.MessageDecoder
  alias Bolty.BoltProtocol.MessageEncoder

  @signature 0x2F

  def encode(bolt_version, extra_parameters)
      when is_tuple(bolt_version) and bolt_version >= {4, 0} do
    message = [MessageEncoder.paging_params(extra_parameters)]
    MessageEncoder.encode(@signature, message)
  end

  def encode(_, _) do
    MessageEncoder.unsupported_version_error(__MODULE__, "DISCARD")
  end

  def prepare_messages(_bolt_version, messages) do
    MessageDecoder.prepare_generic(__MODULE__, messages)
  end
end
