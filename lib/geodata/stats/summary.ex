defmodule GeoData.Stats.Summary do
  @moduledoc """
  Dataset-wide statistics over the stored places.

  Returned by `GeoData.Stats.summary/0`.

  ## Fields

    * `:total` - number of stored places
    * `:by_kind` - place counts keyed by kind, e.g. `%{country: 249, ...}`
    * `:by_continent` - country counts keyed by continent code, e.g.
      `%{"EU" => 51}`

  """

  defstruct total: 0, by_kind: %{}, by_continent: %{}
end
