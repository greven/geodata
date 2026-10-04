defmodule GeoData.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :geodata,
      version: @version,
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {GeoData.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp description do
    "Geo data library built on Debian iso-codes and GeoNames, with locale-aware search and pluggable storage."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{},
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE .formatter.exs usage-rules.md)
    ]
  end

  def cli do
    [
      preferred_envs: [
        "test.all": :test,
        "test.integration": :test
      ]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.7"},
      {:geo, "~> 4.1"},
      {:topo, "~> 1.0"},
      {:localize, "~> 1.3"},
      {:nimble_options, "~> 1.1"},
      {:ecto, "~> 3.14", optional: true},
      {:ecto_sql, "~> 3.14", optional: true},
      {:ecto_sqlite3, "~> 0.25", only: :test, optional: true},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false, optional: true},
      {:git_ops, "~> 2.12", only: :dev, runtime: false}
    ]
  end

  # GeoData is additionally exercised as an external dependency by the small
  # consumer project in `integration/`. Because that is a Mix project of its
  # own, `mix test` does not pick it up; these aliases run it on demand.
  defp aliases do
    [
      "integration.setup": fn _args -> run_in_integration(["deps.get"]) end,
      "test.integration": fn args -> run_in_integration(["test" | args]) end,
      "test.all": ["test", "test.integration"]
    ]
  end

  defp run_in_integration(command) do
    {_, status} =
      System.cmd("mix", command, cd: "integration", into: IO.stream(:stdio, :line))

    if status != 0 do
      System.at_exit(fn _ -> exit({:shutdown, status}) end)
    end
  end
end
