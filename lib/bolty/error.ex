# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.Error do
  @error_map %{
    "Neo.ClientError.Security.Unauthorized" => :unauthorized,
    "Neo.ClientError.Request.Invalid" => :request_invalid,
    "Neo.ClientError.Statement.SemanticError" => :semantic_error,
    "Neo.ClientError.Statement.SyntaxError" => :syntax_error
  }

  @type t() :: %__MODULE__{
          module: module(),
          code: atom(),
          bolt: %{code: atom() | binary(), message: binary() | nil} | nil,
          packstream: %{bits: any() | nil} | nil
        }

  defexception [:module, :code, :bolt, :packstream]

  @spec wrap(module(), atom()) :: t()
  def wrap(module, code) when is_atom(code), do: %__MODULE__{module: module, code: code}

  @spec wrap(module(), String.t()) :: t()
  def wrap(module, code) when is_binary(code), do: wrap(module, to_atom(code))

  @spec wrap(module(), map()) :: t()
  def wrap(module, bolt_error) when is_map(bolt_error),
    do: %__MODULE__{module: module, code: bolt_error.code |> to_atom(), bolt: bolt_error}

  @spec wrap(any(), any(), any()) :: t()
  def wrap(module, code, packstream),
    do: %__MODULE__{module: module, code: code, packstream: packstream}

  @doc """
  Return the code for the given error.

  ### Examples

       iex> {:error, %Bolty.Error{} = error} = do_something()
       iex> Exception.message(error)
       "Unable to perform this action."


  """
  @spec message(t()) :: String.t()
  def message(%__MODULE__{code: code, module: module, bolt: bolt}) do
    cond do
      is_map(bolt) and is_binary(bolt[:message]) ->
        bolt[:message]

      is_atom(module) and Code.ensure_loaded?(module) and
          function_exported?(module, :format_error, 1) ->
        module.format_error(code)

      true ->
        "#{inspect(module)} error: #{inspect(code)}"
    end
  end

  @doc """
  Gets the corresponding atom based on the error code.

  An atom code is already resolved and passes through unchanged; this lets
  callers build an error map with a known atom `code` (e.g.
  `%{code: :unsupported_message_version, message: ...}`) without it being
  collapsed to `:unknown` by the string lookup.
  """
  @spec to_atom(String.t() | atom()) :: atom()
  def to_atom(code) when is_atom(code), do: code

  def to_atom(error_message) when is_binary(error_message) do
    Map.get(@error_map, error_message, :unknown)
  end
end
