# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Mix.Tasks.Changelog do
  use Mix.Task

  @shortdoc "Generate CHANGELOG.md from conventional commits (requires git-cliff)"

  @moduledoc """
  Generates `CHANGELOG.md` from conventional commits using git-cliff.

  Requires git-cliff to be installed:

      brew install git-cliff

  ## Usage

  Regenerate the full changelog:

      mix changelog

  Preview unreleased changes without writing to disk:

      mix changelog --unreleased --bump

  Tag the unreleased section with the next version (writes to CHANGELOG.md):

      mix changelog --tag v0.0.14

  Any flag not listed here is forwarded directly to git-cliff. See
  `git-cliff --help` for the full option set.
  """

  @impl Mix.Task
  def run(args) do
    unless System.find_executable("git-cliff") do
      Mix.raise("""
      git-cliff not found. Install it with:

          brew install git-cliff
      """)
    end

    argv = if args == [], do: ["--output", "CHANGELOG.md"], else: args

    {_, status} = System.cmd("git-cliff", argv, into: IO.stream(:stdio, :line))

    if status != 0 do
      Mix.raise("git-cliff exited with status #{status}")
    end
  end
end
