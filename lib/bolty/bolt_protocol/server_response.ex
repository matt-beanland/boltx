# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.BoltProtocol.ServerResponse do
  @moduledoc false

  import Record

  defrecord :statement_result, [
    :result_run,
    :result_pull,
    :query
  ]

  defrecord :pull_result, [
    :records,
    :success_data
  ]
end
