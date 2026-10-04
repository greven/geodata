defmodule GeodataIntegration.MixProject do
  use Mix.Project

  def project do
    [
      app: :geodata_integration,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: false,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # GeoData is consumed as an external dependency, exactly as a host
  # application would. `override: true` keeps this project on the local
  # checkout even when a shared dependency is pinned elsewhere.
  defp deps do
    [
      {:geodata, path: "..", override: true},
      {:ecto_sql, "~> 3.14"},
      {:ecto_sqlite3, "~> 0.25"},
      {:postgrex, "~> 0.19 or ~> 1.0"}
    ]
  end
end
