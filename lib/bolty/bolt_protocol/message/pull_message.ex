# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.BoltProtocol.Message.PullMessage do
  @moduledoc false

  import Bolty.BoltProtocol.ServerResponse

  alias Bolty.BoltProtocol.MessageDecoder
  alias Bolty.BoltProtocol.MessageEncoder

  @signature 0x3F

  def encode(bolt_version, extra_parameters)
      when is_tuple(bolt_version) and bolt_version >= {4, 0} do
    message = [MessageEncoder.paging_params(extra_parameters)]
    MessageEncoder.encode(@signature, message)
  end

  def encode(_, _) do
    MessageEncoder.unsupported_version_error(__MODULE__, "PULL")
  end

  def prepare_messages(_bolt_version, messages) do
    records = Enum.reduce(messages, [], &group_record/2)

    cond do
      List.keymember?(messages, :ignored, 0) ->
        {:error, Bolty.Error.wrap(__MODULE__, :ignored)}

      List.keymember?(messages, :failure, 0) ->
        {:error, MessageDecoder.failure_error(__MODULE__, messages[:failure])}

      true ->
        {:ok, pull_result(records: records, success_data: messages[:success])}
    end
  end

  def format_error(:unsupported_message_version), do: "PULL message version not supported"
  def format_error(_), do: "unknown error from PULL response"

  defp group_record({:record, data}, acc) do
    [data | acc]
  end

  defp group_record(_other, acc), do: acc
end
