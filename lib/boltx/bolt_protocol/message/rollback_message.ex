defmodule Bolty.BoltProtocol.Message.RollbackMessage do
  @moduledoc false

  alias Bolty.BoltProtocol.MessageEncoder

  @signature 0x13

  def encode(bolt_version) when is_float(bolt_version) and bolt_version >= 3.0 do
    message = []
    MessageEncoder.encode(@signature, message)
  end

  def encode(_) do
    {:error,
     Bolty.Error.wrap(__MODULE__, %{
       code: :unsupported_message_version,
       message: "ROLLBACK message version not supported"
     })}
  end
end
