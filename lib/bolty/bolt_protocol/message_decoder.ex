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

  # Build the `%Bolty.Error{}` for a FAILURE response.
  #
  # A GQL FAILURE (Bolt 5.7+) carries `gql_status`, `description`, `message`,
  # `neo4j_code`, `diagnostic_record` and optionally `cause`. Only the code was
  # renamed (`code` → `neo4j_code`): `message` is the human diagnostic in both
  # eras, while `description` is the boilerplate description of the GQLSTATUS
  # class — "error: syntax error or access rule violation - invalid syntax" for
  # every 42001, whatever went wrong. Preferring `description` therefore threw
  # the useful text away, and did so intermittently, since some error classes
  # append their specifics to it (issue #138).
  #
  # `description` is kept alongside rather than dropped — it is the right thing
  # to show next to a GQLSTATUS — as are the diagnostic record (whose
  # `_position` locates a syntax error) and the `cause` chain, which often
  # carries a more precise status than the outer error.
  @spec failure_error(module(), map()) :: Error.t()
  def failure_error(module, response) do
    Error.wrap(module, gql_failure(response))
  end

  @spec gql_failure(map()) :: Error.bolt_failure()
  defp gql_failure(response) do
    %{
      code: response["neo4j_code"] || response["code"],
      message: response["message"] || response["description"]
    }
    |> put_present(:gql_status, response["gql_status"])
    |> put_present(:description, response["description"])
    |> put_present(:diagnostic_record, response["diagnostic_record"])
    # Normalised recursively: a cause has the shape of a failure, and a caller
    # walking the chain shouldn't switch key styles halfway down.
    |> put_present(:cause, response["cause"] && gql_failure(response["cause"]))
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

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
