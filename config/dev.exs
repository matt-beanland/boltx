import Config

level =
  if System.get_env("DEBUG") do
    :debug
  else
    :info
  end

config :bolty,
  log: false,
  log_hex: false

config :logger, :console,
  level: level,
  format: "$date $time [$level] $metadata$message\n"

config :tzdata, :autoupdate, :disabled
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase
