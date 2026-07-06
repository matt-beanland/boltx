# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.BoltProtocol.MessageEncoder do
  @moduledoc false

  alias Bolty.PackStream
  alias Bolty.Policy

  @max_chunk_size 65_535
  @end_marker <<0x00, 0x00>>
  @tiny_struct_marker 0xB
  @struct8_marker 0xDC
  @struct16_marker 0xDD

  def encode(signature, data, policy \\ %Policy{}) do
    Bolty.Utils.Logger.log_message(:client, :message_type, data)

    encoded =
      signature
      |> do_encode(data, policy)
      |> generate_chunks([])

    Bolty.Utils.Logger.log_client_message_hex(encoded, data)
    encoded |> IO.iodata_to_binary()
  end

  # The standard `{:error, %Bolty.Error{}}` a message module returns from its
  # fallback `encode/_` clause when the negotiated Bolt version is too old to
  # carry that message. `module` is the calling message module (for error
  # context); `name` is the message name, e.g. `"RUN"`.
  @spec unsupported_version_error(module(), String.t()) :: {:error, Bolty.Error.t()}
  def unsupported_version_error(module, name) do
    {:error,
     Bolty.Error.wrap(module, %{
       code: :unsupported_message_version,
       message: "#{name} message version not supported"
     })}
  end

  # The `n`/`qid` paging fields shared by the PULL and DISCARD message extras,
  # each defaulting to `-1` (all records / the last query).
  @spec paging_params(map()) :: %{n: integer(), qid: integer()}
  def paging_params(extra_parameters) do
    %{
      n: Map.get(extra_parameters, :n, -1),
      qid: Map.get(extra_parameters, :qid, -1)
    }
  end

  defp do_encode(signature, list, policy) when length(list) <= 15 do
    [
      <<@tiny_struct_marker::4, length(list)::4, signature>>,
      encode_list_data(list, policy)
    ]
  end

  defp do_encode(signature, list, policy) when length(list) <= 255 do
    [<<@struct8_marker::8, length(list)::8, signature>>, encode_list_data(list, policy)]
  end

  defp do_encode(signature, list, policy) when length(list) <= 65_535 do
    [
      <<@struct16_marker::8, length(list)::16, signature>>,
      encode_list_data(list, policy)
    ]
  end

  defp encode_list_data(data, policy) do
    Enum.map(
      data,
      &PackStream.pack!(&1, policy)
    )
  end

  defp generate_chunks(<<>>, chunks) do
    [chunks, [@end_marker], []]
  end

  defp generate_chunks(data, chunks) do
    data_size = :erlang.iolist_size(data)

    case data_size > @max_chunk_size do
      true ->
        bindata = :erlang.iolist_to_binary(data)
        <<chunk::binary-@max_chunk_size, rest::binary>> = bindata
        new_chunk = format_chunk(chunk)
        generate_chunks(rest, [chunks, new_chunk])

      _ ->
        generate_chunks(<<>>, [chunks, format_chunk(data)])
    end
  end

  defp format_chunk(chunk) do
    [<<:erlang.iolist_size(chunk)::16>>, chunk]
  end
end
