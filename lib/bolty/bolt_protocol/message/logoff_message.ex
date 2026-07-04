# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.BoltProtocol.Message.LogoffMessage do
  @moduledoc false

  alias Bolty.BoltProtocol.MessageEncoder

  @signature 0x6B

  def encode(bolt_version) when is_tuple(bolt_version) and bolt_version >= {5, 1} do
    MessageEncoder.encode(@signature, [])
  end

  def encode(_) do
    {:error,
     Bolty.Error.wrap(__MODULE__, %{
       code: :unsupported_message_version,
       message: "LOGOFF message version not supported"
     })}
  end
end
