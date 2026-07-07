# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.PackStream do
  @moduledoc false

  alias Bolty.PackStream.Packer
  alias Bolty.PackStream.Unpacker
  alias Bolty.Policy

  def pack(term, policy \\ %Policy{}, options \\ []) do
    iodata? = Keyword.get(options, :iodata, false)

    try do
      Packer.pack(term, policy)
    catch
      :throw, error ->
        {:error, error}

      :error, %Protocol.UndefinedError{protocol: Bolty.PackStream.Packer} = exception ->
        {:error, exception}
    else
      iodata when iodata? ->
        {:ok, iodata}

      iodata ->
        {:ok, IO.iodata_to_binary(iodata)}
    end
  end

  @spec pack!(term, Policy.t(), Keyword.t()) :: iodata | no_return
  def pack!(term, policy \\ %Policy{}, options \\ []) do
    case pack(term, policy, options) do
      {:ok, result} ->
        result

      {:error, exception} ->
        raise exception
    end
  end

  @spec unpack(any()) :: {:error, any()} | {:ok, list()}
  def unpack(iodata) do
    try do
      iodata
      |> Unpacker.unpack()
    catch
      :throw, error ->
        {:error, error}
    else
      value ->
        {:ok, value}
    end
  end

  def unpack!(iodata) do
    case unpack(iodata) do
      {:ok, value} ->
        value

      {:error, exception} ->
        raise exception
    end
  end
end
