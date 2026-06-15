# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

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

config :git_ops,
  mix_project: Mix.Project.get!(),
  changelog_file: "CHANGELOG.md",
  repository_url: "https://github.com/diffo-dev/bolty",
  # Each conventional-commit type and the changelog section it appears under.
  types: [
    feat: [header: "Features"],
    fix: [header: "Bug Fixes"],
    perf: [header: "Performance"],
    refactor: [header: "Refactoring"],
    docs: [header: "Documentation"],
    test: [header: "Testing"],
    ci: [header: "CI/CD"],
    style: [header: "Style"],
    chore: [header: "Chores"],
    revert: [header: "Reverts"]
  ],
  # Keep the version in mix.exs (@version) and the dep snippet in README in sync.
  manage_mix_version?: true,
  manage_readme_version: "README.md",
  version_tag_prefix: "v"

config :logger, :console,
  level: level,
  format: "$date $time [$level] $metadata$message\n"

config :tzdata, :autoupdate, :disabled
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase
