defmodule ExAzureCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_azure_core,
      description: description(),
      package: package(),
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      start_permanent: Mix.env() == :prod,
      dialyzer: [
        plt_core_path: "_plts/core"
      ],
      deps: deps(),
      docs: [
        main: "readme",
        extras: [
          "README.md": [title: "Introduction"],
          "guides/authentication.md": [title: "Authentication"],
          LICENSE: [title: "License"]
        ],
        groups_for_extras: [
          Guides: ~r/guides\/.*/
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ExAzureCore.Application, []}
    ]
  end

  def cli do
    [
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.post": :test,
      "coveralls.html": :test,
      "coveralls.cobertura": :test
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:ex_aws, "~> 2.3", optional: true},
      {:ex_aws_cognito_identity, "~> 1.2", optional: true},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:ex_check, "~> 0.14", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:jason, "~> 1.4"},
      {:mimic, "~> 2.0", only: :test},
      {:mix_audit, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:nimble_options, "~> 1.0"},
      {:recode, "~> 0.8", only: [:dev], runtime: false},
      {:req, "~> 0.4"},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:splode, "~> 0.2"},
      {:telemetry, "~> 1.0"},
      {:zoi, "~> 0.11"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description() do
    "An Elixir base library for working with Microsoft Azure services."
  end

  defp package() do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/ex-azure/ex_azure_core.git"}
    ]
  end
end
