if Code.ensure_loaded?(Ecto.Query) do
  defmodule GeoData.Storage.Ecto.Postgres do
    @moduledoc false

    # Detects which PostgreSQL extensions a repo has installed, so optional
    # features (pg_trgm fuzzy search today, PostGIS proximity later) can be
    # enabled only when the database supports them. The result is cached per
    # repo in `:persistent_term`; call `reset/1` after installing an extension
    # if a detection already happened.

    @cache {__MODULE__, :extensions}

    @doc """
    Returns the set of extension names installed in `repo`, or an empty set for
    non-PostgreSQL repos.
    """
    def extensions(repo) do
      case :persistent_term.get({@cache, repo}, :miss) do
        :miss ->
          set = detect(repo)
          :persistent_term.put({@cache, repo}, set)
          set

        set ->
          set
      end
    end

    @doc """
    Returns whether `repo` has the `pg_trgm` extension installed.
    """
    def pg_trgm?(repo), do: MapSet.member?(extensions(repo), "pg_trgm")

    @doc """
    Returns whether `repo` has the `postgis` extension installed.
    """
    def postgis?(repo), do: MapSet.member?(extensions(repo), "postgis")

    @doc """
    Clears the cached detection for `repo`.
    """
    def reset(repo) do
      :persistent_term.erase({@cache, repo})
      :ok
    end

    defp detect(repo) do
      if postgres?(repo) do
        %{rows: rows} = repo.query!("SELECT extname FROM pg_extension")
        rows |> List.flatten() |> MapSet.new()
      else
        MapSet.new()
      end
    end

    defp postgres?(repo), do: repo.__adapter__() == Ecto.Adapters.Postgres
  end
end
