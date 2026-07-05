# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.BoltProtocol.Message.RollbackMessage do
  @moduledoc false

  alias Bolty.BoltProtocol.MessageEncoder

  @signature 0x13

  def encode(bolt_version) when is_tuple(bolt_version) and bolt_version >= {3, 0} do
    message = []
    MessageEncoder.encode(@signature, message)
  end

  def encode(_) do
    MessageEncoder.unsupported_version_error(__MODULE__, "ROLLBACK")
  end
end
