defmodule GeoData.Search.Result do
  @moduledoc """
  A page of search results.

  ## Fields

    * `:places` - the matching `GeoData.Place` records for this page
    * `:total` - total number of matches across all pages, or `nil` when the
      query was run with `count: false` (so the extra count query is skipped)
    * `:limit` - the requested page size
    * `:offset` - the requested offset

  """

  defstruct places: [], total: 0, limit: nil, offset: 0
end
