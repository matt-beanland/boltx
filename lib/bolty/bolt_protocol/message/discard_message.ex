# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.BoltProtocol.Message.DiscardMessage do
  @moduledoc false

  alias Bolty.BoltProtocol.MessageEncoder

  @signature 0x2F

  def encode(bolt_version, extra_parameters)
      when is_tuple(bolt_version) and bolt_version >= {4, 0} do
    message = [get_extra_parameters(extra_parameters)]
    MessageEncoder.encode(@signature, message)
  end

  def encode(_, _) do
    {:error,
     Bolty.Error.wrap(__MODULE__, %{
       code: :unsupported_message_version,
       message: "DISCARD message version not supported"
     })}
  end

  def prepare_messages(_bolt_version, messages) do
    case hd(messages) do
      {:success, response} ->
        {:ok, response}

      {:failure, response} ->
        {:error,
         Bolty.Error.wrap(__MODULE__, %{
           code: response["neo4j_code"] || response["code"],
           message: response["description"] || response["message"]
         })}
    end
  end

  defp get_extra_parameters(extra_parameters) do
    %{
      n: Map.get(extra_parameters, :n, -1),
      qid: Map.get(extra_parameters, :qid, -1)
    }
  end
end
