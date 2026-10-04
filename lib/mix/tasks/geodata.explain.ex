if Code.ensure_loaded?(Ecto.Query) do
  defmodule Mix.Tasks.Geodata.Explain do
    @shortdoc "Explains PostgreSQL query plans for GeoData searches"

    @moduledoc """
    Shows how PostgreSQL executes a GeoData search.

        mix geodata.explain lisbon
        mix geodata.explain "sao paulo" --match token --limit 10
        mix geodata.explain lisbom --match fuzzy --fuzziness 2
        mix geodata.explain lisbon --no-count
        mix geodata.explain --kind city --country PT

    The search runs through `GeoData.Search.Ecto`; the task captures the SQL it
    generates and prints `EXPLAIN (ANALYZE, BUFFERS)` for the page query and the
    total count. It warns about sequential scans, which usually mean an index is
    missing or an `OR` arm is not indexable.

    Requires an Ecto engine backed by PostgreSQL:

        config :geodata, search: GeoData.Search.Ecto
        config :geodata, GeoData.Storage.Ecto, repo: MyApp.Repo

    This is a read-only diagnostic; it changes no data.

    ## Options

      * `--match` - `exact`, `prefix` (default), `token`, `contains` or `fuzzy`
      * `--fuzziness` - `0`, `1` (default) or `2`, for `--match fuzzy`
      * `--limit`, `--offset` - paging
      * `--no-count` - skip the total count query (and its plan)
      * `--kind`, `--country`, `--subdivision`, `--continent` - comma-separated
        filters
    """

    use Mix.Task

    alias GeoData.Place
    alias GeoData.Search.Ecto, as: SearchEcto

    @switches [
      match: :string,
      fuzziness: :integer,
      limit: :integer,
      offset: :integer,
      kind: :string,
      country: :string,
      subdivision: :string,
      continent: :string,
      count: :boolean,
      help: :boolean
    ]

    @match_modes [:exact, :prefix, :token, :contains, :fuzzy]

    @rows_removed_warning 10_000

    @impl true
    def run(argv) do
      {cli, args, invalid} = OptionParser.parse(argv, strict: @switches)

      if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")

      if cli[:help] do
        Mix.shell().info(@moduledoc)
      else
        do_run(cli, args)
      end
    end

    defp do_run(cli, args) do
      Mix.Task.run("app.start")

      repo = repo!()
      opts = options(cli)
      {result, queries} = capture(fn -> run_search(text(args), opts) end)

      if queries == [] do
        Mix.raise(
          "no GeoData query was issued; check that GeoData.Search.Ecto and the Ecto storage are configured"
        )
      end

      summary(result, queries)
      explain_all(repo, queries, opts)
    end

    @doc false
    def handle_query(_event, measurements, metadata, pid) do
      sql = metadata[:query]

      if is_binary(sql) and String.contains?(sql, "geodata_places") do
        send(
          pid,
          {:geodata_query,
           %{
             sql: sql,
             params: metadata[:params] || [],
             time: measurements[:total_time],
             rows: num_rows(metadata[:result])
           }}
        )
      end
    end

    defp run_search(text, opts) do
      case GeoData.search(text, opts) do
        {:ok, result} -> result
        {:error, error} -> Mix.raise(Exception.message(error))
      end
    end

    defp capture(fun) do
      repo = SearchEcto.repo()
      prefix = repo.config()[:telemetry_prefix] || [:geodata, :repo]
      id = {__MODULE__, make_ref()}

      :telemetry.attach_many(id, [prefix ++ [:query]], &__MODULE__.handle_query/4, self())

      try do
        {fun.(), drain()}
      after
        :telemetry.detach(id)
      end
    end

    defp drain(acc \\ []) do
      receive do
        {:geodata_query, query} -> drain([query | acc])
      after
        0 -> Enum.reverse(acc)
      end
    end

    defp summary(%{total: total, places: places}, queries) do
      Mix.shell().info(
        "search returned #{length(places)} place(s) in #{length(queries)} query(ies); total: #{inspect(total)}"
      )
    end

    defp explain_all(repo, queries, opts) do
      threshold = if opts[:match] == :fuzzy, do: threshold(opts[:fuzziness] || 1)

      repo.transaction(fn ->
        if threshold do
          repo.query!(
            "SELECT set_config('pg_trgm.word_similarity_threshold', $1, true)",
            [threshold]
          )
        end

        count = length(queries)

        queries
        |> Enum.with_index(1)
        |> Enum.each(fn {query, index} -> explain_one(repo, query, index, count) end)
      end)
    end

    defp explain_one(repo, query, index, count) do
      Mix.shell().info("\n## Query #{index}/#{count} — #{label(query.sql)}")
      Mix.shell().info("baseline: #{ms(query.time)} ms, #{inspect(query.rows)} row(s)")
      Mix.shell().info("sql: #{query.sql}")

      case explain(repo, query.sql, query.params) do
        {:ok, plan} ->
          Mix.shell().info("\n#{plan}")
          warn(plan)

        {:error, error} ->
          Mix.shell().error("could not EXPLAIN: #{Exception.message(error)}")
      end
    end

    defp explain(repo, sql, params) do
      case repo.query("EXPLAIN (ANALYZE, BUFFERS) " <> sql, params) do
        {:ok, %{rows: rows}} -> {:ok, rows |> List.flatten() |> Enum.join("\n")}
        {:error, error} -> {:error, error}
      end
    end

    defp warn(plan) do
      cond do
        plan =~ ~r/\bSeq Scan\b/ ->
          Mix.shell().info("""
          WARNING: sequential scan — no usable index for (part of) this query.
          Check that the GeoData migration is applied (mix ecto.migrate) so the
          iso_3166_2 and geonames_id indexes exist (they keep every OR arm
          indexable), and that pg_trgm is installed for fuzzy matching.
          """)

        removed(plan) > @rows_removed_warning ->
          Mix.shell().info("""
          WARNING: scanned #{removed(plan)} rows to return a few — the planner is
          filtering after an index walk rather than seeking. If the table was
          just ingested, run ANALYZE geodata_places so it has statistics;
          otherwise the search term is simply broad.
          """)

        true ->
          Mix.shell().info("OK: index-based plan")
      end
    end

    defp removed(plan) do
      ~r/Rows Removed by (?:Filter|Index Recheck): (\d+)/
      |> Regex.scan(plan)
      |> Enum.map(fn [_, count] -> String.to_integer(count) end)
      |> Enum.sum()
    end

    defp label(sql) do
      if String.contains?(sql, "count("), do: "total count", else: "page"
    end

    defp options(cli) do
      [search: SearchEcto]
      |> put(:match, cli[:match], &match_mode/1)
      |> put(:fuzziness, cli[:fuzziness], & &1)
      |> put(:limit, cli[:limit], & &1)
      |> put(:offset, cli[:offset], & &1)
      |> put(:count, cli[:count], & &1)
      |> where_options(cli)
    end

    defp put(opts, _key, nil, _fun), do: opts
    defp put(opts, key, value, fun), do: Keyword.put(opts, key, fun.(value))

    defp where_options(opts, cli) do
      filters =
        [
          kind: cli[:kind] && kinds(cli[:kind]),
          country: cli[:country] && csv(cli[:country]),
          subdivision: cli[:subdivision] && csv(cli[:subdivision]),
          continent: cli[:continent] && csv(cli[:continent])
        ]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)

      if filters == [], do: opts, else: Keyword.put(opts, :where, filters)
    end

    defp match_mode(value) do
      mode = String.to_atom(value)

      if mode in @match_modes do
        mode
      else
        Mix.raise("invalid --match #{inspect(value)}, expected one of #{inspect(@match_modes)}")
      end
    end

    defp kinds(value) do
      value
      |> csv()
      |> Enum.map(&String.to_atom/1)
      |> Enum.reject(&(&1 not in Place.kinds()))
    end

    defp csv(value) do
      value
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
    end

    defp text([]), do: nil
    defp text(args), do: args |> Enum.join(" ") |> String.trim()

    defp threshold(0), do: "1.0"
    defp threshold(1), do: "0.6"
    defp threshold(2), do: "0.4"

    defp repo! do
      repo = SearchEcto.repo()

      if repo.__adapter__() != Ecto.Adapters.Postgres do
        Mix.raise(
          "mix geodata.explain needs PostgreSQL, but the configured repo uses #{inspect(repo.__adapter__())}"
        )
      end

      repo
    rescue
      error in [ArgumentError, UndefinedFunctionError] -> Mix.raise(Exception.message(error))
    end

    defp num_rows({:ok, %{num_rows: rows}}), do: rows
    defp num_rows(_result), do: nil

    defp ms(nil), do: "?"
    defp ms(native), do: System.convert_time_unit(native, :native, :millisecond)
  end
end
