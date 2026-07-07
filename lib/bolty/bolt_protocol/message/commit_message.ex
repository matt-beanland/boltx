# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.BoltProtocol.Message.CommitMessage do
  @moduledoc false

  alias Bolty.BoltProtocol.MessageEncoder

  @signature 0x12

  def encode(bolt_version) when is_tuple(bolt_version) and bolt_version >= {3, 0} do
    message = []
    MessageEncoder.encode(@signature, message)
  end

  def encode(_) do
    MessageEncoder.unsupported_version_error(__MODULE__, "COMMIT")
  end
end
