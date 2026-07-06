# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

try do
  Code.eval_file(".iex.exs", "~")
rescue
  Code.LoadError -> :rescued
end

alias Bolty.{Response, Types, Utils}
alias Bolty

# Example options for an iex dev session — matches the keys
# Bolty.Client.Config.new/1 reads. Default Bolt port is 7687.
_dev_opts = [
  uri: "bolt://localhost:7687",
  auth: [username: "neo4j", password: "boltyPassword"],
  pool_size: 5,
  max_overflow: 1
]

Mix.shell().info([
  :green,
  """
  Dev shell ready. Example:

      {:ok, conn} =
        Bolty.start_link(
          uri: "bolt://localhost:7687",
          auth: [username: "neo4j", password: "boltyPassword"]
        )

      Bolty.query!(conn, "UNWIND range(1, 10) AS n RETURN n")
      Bolty.query!(conn, "RETURN 1 AS n") |> Bolty.Response.first()

  --- ✄  -------------------------------------------------

  """
])
