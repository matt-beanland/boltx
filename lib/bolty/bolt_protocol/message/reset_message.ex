# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.BoltProtocol.Message.ResetMessage do
  @moduledoc false

  alias Bolty.BoltProtocol.MessageEncoder

  @signature 0x0F

  def encode(bolt_version) when is_tuple(bolt_version) and bolt_version >= {3, 0} do
    MessageEncoder.encode(@signature, [])
  end

  def encode(_) do
    {:error,
     Bolty.Error.wrap(__MODULE__, %{
       code: :unsupported_message_version,
       message: "RESET message version not supported"
     })}
  end
end
