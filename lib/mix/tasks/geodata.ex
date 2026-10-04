defmodule Mix.Tasks.Geodata do
  use Mix.Task

  @shortdoc "Prints GeoData help information"

  @moduledoc """
  Prints the GeoData tasks and their information.

      mix geodata

  To print the GeoData version, pass `-v` or `--version`:

      mix geodata --version
  """

  @impl true
  @doc false
  def run(["-v"]), do: version()
  def run(["--version"]), do: version()

  def run([]), do: general()

  def run(_args) do
    Mix.raise("Invalid arguments, expected: mix geodata")
  end

  defp version do
    _ = Application.load(:geodata)
    Mix.shell().info("GeoData v#{Application.spec(:geodata, :vsn)}")
  end

  defp general do
    version()
    Mix.shell().info("\n## Tasks\n")
    Mix.Tasks.Help.run(["--search", "geodata."])
  end
end
