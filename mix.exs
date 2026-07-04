# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.Mixfile do
  use Mix.Project

  @version "0.2.1"
  @url_docs "https://hexdocs.pm/bolty"
  @url_github "https://github.com/diffo-dev/bolty"

  def project do
    [
      app: :bolty,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      package: package(),
      description: "Neo4j driver for Elixir, using the fast Bolt protocol",
      name: "Bolty",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      docs: docs(),
      dialyzer: [
        plt_add_apps: [:jason, :poison, :mix],
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts",
        ignore_warnings: ".dialyzer_ignore.exs"
      ],
      test_coverage: [
        tool: ExCoveralls,
        summary: [
          threshold: 70
        ]
      ],
      aliases: aliases()
    ]
  end

  def cli do
    [
      preferred_envs: [
        bench: :bench,
        credo: :dev,
        bolty: :test,
        coveralls: :test,
        "coveralls.html": :test,
        "coveralls.travis": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssl, :public_key]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", &enable_git_hooks/1],
      test: [
        "test"
      ]
    ]
  end

  # Point git at the repo's shared hooks (.githooks/pre-push runs the fast lint
  # checks before a push). Idempotent; run via `mix setup`.
  defp enable_git_hooks(_args) do
    case System.cmd("git", ["config", "core.hooksPath", ".githooks"], stderr_to_stdout: true) do
      {_, 0} -> Mix.shell().info("Git hooks enabled (core.hooksPath = .githooks)")
      {out, _} -> Mix.shell().error("Could not enable git hooks: #{out}")
    end
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    %{
      files: [
        "lib",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "usage-rules.md",
        "LICENSE",
        "NOTICE",
        "LICENSES",
        "REUSE.toml"
      ],
      licenses: ["Apache-2.0"],
      maintainers: [
        "Matt Beanland"
      ],
      links: %{
        "Docs" => @url_docs,
        "Github" => @url_github
      }
    }
  end

  defp docs() do
    [
      source_ref: "v#{@version}",
      source_url: @url_github,
      main: "readme",
      extras: ["README.md", "guides/telemetry.md", "CHANGELOG.md"]
    ]
  end

  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:db_connection, "~> 2.7"},
      {:telemetry, "~> 1.0"},
      {:jason, "~> 1.4", optional: true},
      {:poison, "~> 6.0", optional: true},

      # Testing dependencies
      {:excoveralls, "~> 0.18.0", optional: true, only: [:test, :dev]},
      {:tzdata, "~> 1.1", only: [:test, :dev]},
      {:stream_data, "~> 1.0", only: [:test, :dev]},

      # Benchmarking dependencies
      {:benchee, "~> 1.3", optional: true, only: [:dev, :test]},
      {:benchee_html, "~> 1.0.0", optional: true, only: [:dev]},

      # Linting dependencies
      {:credo, "~> 1.7.3", only: [:dev]},
      {:dialyxir, "~> 1.4.3", only: [:dev], runtime: false},

      # Release dependencies (conventional-commit changelog + version bump)
      {:git_ops, "~> 2.7", only: [:dev], runtime: false},

      # Documentation dependencies
      # Run me like this: `mix docs`
      {:ex_doc, "~> 0.29", only: :dev, runtime: false}
    ]
  end
end
