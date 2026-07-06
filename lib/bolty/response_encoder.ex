# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.ResponseEncoder do
  @moduledoc """
  This module provides functions to encode a query result or data containing Bolty.Types
  into various format.

  For now, only JSON is supported.

  Encoding is handled by protocols to allow override if a specific implemention is required.
  See targeted protocol documentation for more information

  """

  @doc """
  Encode the data in json format.

  This is done in 2 steps:
  - first, the data is converted into a jsonable format
  - the result is encoded in json via Elixir's built-in `JSON`

  Step 1 is overridable via the `Bolty.ResponseEncoder.Json` protocol.

  `Bolty.Types.*` structs can also be handed straight to `JSON.encode!/1`
  (bolty ships the `JSON.Encoder` implementations); this function is the
  convenience wrapper that runs the jsonable conversion first.

  ## Example

      iex> data = %{"t1" => %Bolty.Types.Node{
      ...>     id: 69,
      ...>     labels: ["Test"],
      ...>     properties: %{
      ...>       "created" => %Bolty.Types.DateTimeWithTZOffset{
      ...>         naive_datetime: ~N[2016-05-24 13:26:08.543],
      ...>         timezone_offset: 7200
      ...>       },
      ...>       "uuid" => 12345
      ...>     }
      ...>   }
      ...> }
      iex> {:ok, json} = Bolty.ResponseEncoder.encode(data, :json)
      iex> decoded = JSON.decode!(json)
      iex> decoded["t1"]["id"]
      69
      iex> decoded["t1"]["properties"]["created"]
      "2016-05-24T13:26:08.543+02:00"

      iex> match?({:error, _}, Bolty.ResponseEncoder.encode(<<0xFF>>, :json))
      true
  """
  @spec encode(any(), :json) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def encode(response, :json) do
    {:ok,
     response
     |> jsonable_response()
     |> JSON.encode!()}
  rescue
    e -> {:error, e}
  end

  @doc """
  Encode the data in json format.

  Similar to `encode/1` except it will unwrap the error tuple and raise in case of errors.

  ## Example

      iex> data = %{"t1" => %Bolty.Types.Node{
      ...>     id: 69,
      ...>     labels: ["Test"],
      ...>     properties: %{
      ...>       "created" => %Bolty.Types.DateTimeWithTZOffset{
      ...>         naive_datetime: ~N[2016-05-24 13:26:08.543],
      ...>         timezone_offset: 7200
      ...>       },
      ...>       "uuid" => 12345
      ...>     }
      ...>   }
      ...> }
      iex> json = Bolty.ResponseEncoder.encode!(data, :json)
      iex> JSON.decode!(json)["t1"]["labels"]
      ["Test"]
  """
  @spec encode!(any(), :json) :: String.t() | no_return()
  def encode!(response, :json) do
    response
    |> jsonable_response()
    |> JSON.encode!()
  end

  defp jsonable_response(response) do
    response
    |> Bolty.ResponseEncoder.Json.encode()
  end
end
