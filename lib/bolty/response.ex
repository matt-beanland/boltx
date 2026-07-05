# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.Response do
  @moduledoc """
  The result of a single Bolt RUN/PULL exchange returned by `Bolty.query/4`
  and friends.

  Fields:

    * `results` — row-major list of `%{field => value}` maps; what you usually want.
    * `fields` — list of returned field names in column order.
    * `records` — untransformed column-major rows, parallel to `fields`.
    * `plan`, `profile`, `stats`, `notifications`, `type`, `bookmark` — server
      metadata from the trailing SUCCESS message; shapes follow the Bolt
      protocol.

  Implements `Enumerable` over `results` — `Enum.map/2`, `Enum.count/1`, and
  `for` comprehensions all work. Use `Bolty.Response.first/1` for the common
  single-row case.
  """

  import Bolty.BoltProtocol.ServerResponse

  @type t :: %__MODULE__{
          results: list,
          fields: list,
          records: list,
          plan: map,
          notifications: list,
          stats: list | map,
          profile: any,
          type: String.t(),
          bookmark: String.t()
        }

  @type key :: any
  @type value :: any
  @type acc :: any
  @type element :: any

  defstruct results: [],
            fields: nil,
            records: [],
            plan: nil,
            notifications: [],
            stats: [],
            profile: nil,
            type: nil,
            bookmark: nil

  @spec new(tuple()) :: t()
  def new(
        statement_result(
          result_run: result_run,
          result_pull: pull_result(records: records, success_data: success_data)
        )
      ) do
    fields = Map.get(result_run, "fields", [])

    %__MODULE__{
      results: create_results(fields, records),
      fields: fields,
      records: records,
      plan: Map.get(success_data, "plan", nil),
      notifications: Map.get(success_data, "notifications", []),
      stats: Map.get(success_data, "stats", []),
      profile: Map.get(success_data, "profile", nil),
      type: Map.get(success_data, "type", nil),
      bookmark: Map.get(success_data, "bookmark", nil)
    }
  end

  @spec first(t()) :: map() | nil
  def first(%__MODULE__{results: []}), do: nil
  def first(%__MODULE__{results: [head | _tail]}), do: head

  defp create_results(fields, records) do
    records
    |> Enum.map(fn recs -> Enum.zip(fields, recs) end)
    |> Enum.map(fn data -> Enum.into(data, %{}) end)
  end
end
