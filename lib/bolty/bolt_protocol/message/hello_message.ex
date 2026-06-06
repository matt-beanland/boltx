# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.BoltProtocol.Message.HelloMessage do
  @moduledoc false

  import Bolty.BoltProtocol.Message.Shared.AuthHelper

  alias Bolty.BoltProtocol.MessageEncoder

  @signature 0x01

  def encode(bolt_version, fields) when is_float(bolt_version) and bolt_version >= 5.1 do
    message = [
      bolt_version
      |> get_user_agent(fields)
      |> Map.merge(get_bolt_agent(fields))
      |> Map.merge(get_extra_parameters(bolt_version, fields))
    ]

    MessageEncoder.encode(@signature, message)
  end

  def encode(bolt_version, fields) when is_float(bolt_version) and bolt_version >= 3.0 do
    message = [Map.merge(get_auth_params(fields), get_user_agent(bolt_version, fields))]
    MessageEncoder.encode(@signature, message)
  end

  def encode(_, _) do
    {:error,
     Bolty.Error.wrap(__MODULE__, %{
       code: :unsupported_message_version,
       message: "HELLO message version not supported"
     })}
  end

  defp get_extra_parameters(bolt_version, fields) do
    min_severity = Keyword.get(fields, :notifications_minimum_severity)

    # Bolt 5.6 renamed notifications_disabled_categories → notifications_disabled_classifications
    {categories_key, categories_value} =
      if bolt_version >= 5.6 do
        value =
          Keyword.get(fields, :notifications_disabled_classifications) ||
            Keyword.get(fields, :notifications_disabled_categories)

        {:notifications_disabled_classifications, value}
      else
        {:notifications_disabled_categories,
         Keyword.get(fields, :notifications_disabled_categories)}
      end

    %{}
    |> then(fn acc ->
      if min_severity, do: Map.put(acc, :notifications_minimum_severity, min_severity), else: acc
    end)
    |> then(fn acc ->
      if categories_value, do: Map.put(acc, categories_key, categories_value), else: acc
    end)
  end
end
