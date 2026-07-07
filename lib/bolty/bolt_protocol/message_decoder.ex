# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.BoltProtocol.MessageDecoder do
  @moduledoc false

  alias Bolty.Error
  alias Bolty.PackStream

  @type in_signature :: :failure | :ignored | :record | :success
  @type encoded :: <<_::16, _::_*8>>
  @type decoded :: {in_signature(), any()}

  # Interpret the head of a decoded message list for a message type whose
  # response is a single SUCCESS/FAILURE (with IGNORED possible mid-pipeline).
  # Returns `{:ok, data}` on success, or `{:error, %Bolty.Error{}}` wrapped with
  # `module` for context. Message modules with a richer response (e.g. PULL
  # aggregating RECORDs) build their own result but reuse `failure_error/2`.
  @spec prepare_generic(module(), [decoded()]) :: {:ok, any()} | {:error, Error.t()}
  def prepare_generic(module, messages) do
    case hd(messages) do
      {:success, response} -> {:ok, response}
      {:ignored, _} -> {:error, Error.wrap(module, :ignored)}
      {:failure, response} -> {:error, failure_error(module, response)}
    end
  end

  # Build the `%Bolty.Error{}` for a FAILURE response, reading the GQL-compliant
  # `neo4j_code`/`description` fields (Bolt 5.7+) and falling back to the legacy
  # `code`/`message` fields.
  @spec failure_error(module(), map()) :: Error.t()
  def failure_error(module, response) do
    Error.wrap(module, %{
      code: response["neo4j_code"] || response["code"],
      message: response["description"] || response["message"]
    })
  end

  @tiny_struct_marker 0xB
  @success_signature 0x70
  @failure_signature 0x7F
  @record_signature 0x71
  @ignored_signature 0x7E

  @spec decode(encoded()) :: decoded()
  def decode(<<@tiny_struct_marker::4, nb_entries::4, @success_signature, data::binary>>) do
    build_response(:success, data, nb_entries)
  end

  @spec decode(encoded()) :: decoded()
  def decode(<<@tiny_struct_marker::4, nb_entries::4, @failure_signature, data::binary>>) do
    build_response(:failure, data, nb_entries)
  end

  @spec decode(encoded()) :: decoded()
  def decode(<<@tiny_struct_marker::4, nb_entries::4, @record_signature, data::binary>>) do
    build_response(:record, data, nb_entries)
  end

  @spec decode(encoded()) :: decoded()
  def decode(<<@tiny_struct_marker::4, nb_entries::4, @ignored_signature, data::binary>>) do
    build_response(:ignored, data, nb_entries)
  end

  defp build_response(message_type, data, nb_entries) do
    Bolty.Utils.Logger.log_message(:server, message_type, data, :hex)

    response =
      case PackStream.unpack(data) do
        {:ok, response} when nb_entries == 1 ->
          List.first(response)

        {:ok, response} ->
          response

        # Corrupt/undecodable server payload (e.g. an unknown marker). Raise the
        # %Bolty.Error{} so the connection tears down rather than proceeding with
        # a partially decoded message.
        {:error, %Bolty.Error{} = error} ->
          raise error
      end

    Bolty.Utils.Logger.log_message(:server, message_type, response)
    {message_type, response}
  end
end
