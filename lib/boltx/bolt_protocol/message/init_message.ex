defmodule Bolty.BoltProtocol.Message.InitMessage do
  @moduledoc false

  import Bolty.BoltProtocol.Message.Shared.AuthHelper

  alias Bolty.BoltProtocol.MessageEncoder

  @signature 0x01

  def encode(bolt_version, fields) when is_float(bolt_version) and bolt_version >= 1.0 do
    message = [get_user_agent(fields), get_auth_params(fields)]
    MessageEncoder.encode(@signature, message)
  end

  def encode(_, _) do
    {:error,
     Bolty.Error.wrap(__MODULE__, %{
       code: :unsupported_message_version,
       message: "INIT message version not supported"
     })}
  end
end
