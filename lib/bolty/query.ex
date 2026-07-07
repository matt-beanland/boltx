# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.Query do
  @moduledoc false
  # Internal: the struct wrapping a single statement + `extra` options, built by
  # `Bolty.query/4` and passed through the `DBConnection.Query` protocol. Not
  # part of the public API — construct queries via `Bolty.query/4`.

  @typedoc """
  Extra contains additional options. _Introduced in bolt 3_

  * `:bookmarks` -  is a list of strings containing some kind of bookmark identification, e.g.,
   ["neo4j-bookmark-transaction:1", "neo4j-bookmark-transaction:2"]. (default: `[]`).

  * `:mode` - specifies what kind of server the RUN message is targeting. For write access
   use "w" and for read access use "r". (default: `w`).

  * `:db` - specifies the database name for multi-database to select where the transaction
   takes place. null and "" denote the server-side configured default database.
   (default: `null`) _Introduced in bolt 4.0_

  * `:tx_metadata` - is a map that can contain some metadata information, mainly used for logging. (default: `null`)
  """
  @type extra() :: %{
          optional(:bookmarks) => [String.t()],
          optional(:mode) => String.t(),
          optional(:db) => String.t() | nil,
          optional(:tx_metadata) => map()
        }
  @type t :: %__MODULE__{
          statement: String.t(),
          extra: extra()
        }
  defstruct statement: "",
            extra: %{}
end

defmodule Bolty.Queries do
  @moduledoc false
  # Internal: the struct wrapping a `;`-separated batch + shared `extra`, built
  # by `Bolty.query_many/4`. Not part of the public API — use `query_many/4`.

  @type t :: %__MODULE__{
          statement: String.t(),
          extra: Bolty.Query.extra()
        }
  defstruct statement: "",
            extra: %{}
end

defimpl DBConnection.Query, for: [Bolty.Query, Bolty.Queries, Bolty.ConnectionInfo] do
  def describe(query, _), do: query

  def parse(query, _), do: query

  def encode(_query, data, _), do: data

  def decode(_, result, _), do: result
end
