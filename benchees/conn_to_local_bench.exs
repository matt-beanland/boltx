# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

# benchmark the time it takes to open connections to a local neo4j server.
# Misc...
#
# What I want:
#
# - I want to measure the time it takes to open a connection and run
#   a simple query
# - I want to demonstrate how saving and reusing a connection (where
#   applicable) takes less time compared with a similar code where
#   I'm creating a new connection for every query
#
# Sample from a quick run:
#
#    $ mix run benchees/conn_to_local_bench.exs
#
#    Operating System: macOS
#    CPU Information: Intel(R) Core(TM) i7-4770HQ CPU @ 2.20GHz
#    Number of Available Cores: 8
#    Available memory: 17.179869184 GB
#    Elixir 1.5.0
#    Erlang 20.0
#    Benchmark suite executing with the following configuration:
#    warmup: 2.00 s
#    time: 1.00 s
#    parallel: 1
#    inputs: none specified
#    Estimated total run time: 6.00 s
#
#    Benchmarking  new conn...
#    Benchmarking same conn...
#
#    Name                ips        average  deviation         median
#    same conn        1.46 K        0.68 ms    ±20.73%        0.64 ms
#     new conn        0.47 K        2.15 ms    ±67.17%        1.98 ms
#
#    Comparison:
#    same conn        1.46 K
#     new conn        0.47 K - 3.14x slower

opts = [
  uri: System.get_env("BOLT_URI", "bolt://localhost:7687"),
  auth: [
    username: System.get_env("BOLT_USER", "neo4j"),
    password: System.get_env("BOLT_PWD", "boltyPassword")
  ],
  pool_size: 1
]

{:ok, conn} = Bolty.start_link(opts)

simple_cypher = """
  MATCH (p:Person)-[r:WROTE]->(b:Book {title: 'The Name of the Wind'})
  RETURN p
"""

new_conn = fn ->
  {:ok, c} = Bolty.start_link(opts)
  c
end

Benchee.run(
  %{
    "same conn" => fn -> Bolty.query(conn, simple_cypher) end,
    " new conn" => fn -> Bolty.query(new_conn.(), simple_cypher) end
  },
  time: 1
)
