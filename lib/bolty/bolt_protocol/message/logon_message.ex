# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.BoltProtocol.Message.LogonMessage do
  @moduledoc false

  import Bolty.BoltProtocol.Message.Shared.AuthHelper

  alias Bolty.BoltProtocol.MessageEncoder

  @signature 0x6A

  def encode(bolt_version, fields) when is_tuple(bolt_version) and bolt_version >= {3, 0} do
    message = [get_auth_params(fields)]
    MessageEncoder.encode(@signature, message)
  end

  def encode(_, _) do
    MessageEncoder.unsupported_version_error(__MODULE__, "LOGON")
  end
end
