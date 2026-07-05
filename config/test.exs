# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

import Config

# Example config only — the test suite reads its options directly from
# Bolty.TestHelper.opts/0 rather than from Application env. Kept in sync
# with the keys Bolty.Client.Config.new/1 actually consumes so anyone
# copy-pasting from here gets something that works.
config :bolty, Bolt,
  uri: "bolt://localhost:7687",
  auth: [username: "neo4j", password: "password"],
  pool_size: 10,
  max_overflow: 2

level =
  if System.get_env("DEBUG") do
    :debug
  else
    :info
  end

config :bolty,
  log: true,
  log_hex: false

config :logger, :console,
  level: level,
  format: "$date $time [$level] $metadata$message\n"

config :elixir, :time_zone_database, Tz.TimeZoneDatabase
