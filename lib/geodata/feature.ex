defmodule GeoData.Feature do
  @moduledoc """
  Semantic names for GeoNames feature classifications.

  GeoNames tags every place with a `feature_class` (one letter, one of `A`,
  `H`, `L`, `P`, `R`, `S`, `T`, `U`, `V`) and a more specific `feature_code`
  (e.g. `MT` for a mountain, `LK` for a lake). Tis module maps human-friendly
  group names to the underlying codes and class letters.

  `GeoData.Search` uses it for the `:feature_code` and `:feature_class`
  filters, so groups can be used directly:

      GeoData.search(where: [feature_code: :mountain])
      GeoData.search(where: [feature_class: :landforms], order_by: :name)

  Both the singular code groups (`codes/1`) and the whole-class aliases
  (`classes/1`) are curated here; `groups/0` and `classes/0` list what is
  available. Raw codes and class letters keep working unchanged.

  ## Examples

      iex> GeoData.Feature.codes(:mountain)
      {:ok, ["MT", "MTS"]}

      iex> GeoData.Feature.classes(:landforms)
      {:ok, ["T"]}

      iex> GeoData.Feature.codes("mt")
      {:ok, ["MT"]}

      iex> GeoData.Feature.codes(:bogus)
      :error

  """

  @classes %{
    administrative: ["A"],
    hydrography: ["H"],
    areas: ["L"],
    populated: ["P"],
    roads: ["R"],
    spots: ["S"],
    landforms: ["T"],
    undersea: ["U"],
    vegetation: ["V"]
  }

  @groups %{
    capital: ["PPLC"],
    admin_seat: ["PPLA", "PPLA2", "PPLA3", "PPLA4", "PPLA5", "PPLG", "PPLS"],
    city: ["PPL", "PPLC", "PPLA", "PPLA2", "PPLA3", "PPLA4", "PPLA5", "PPLG", "PPLS"],
    section: ["PPLX"],
    locality: ["PPLL", "PPLF", "PPLH", "PPLQ", "PPLR", "PPLW"],
    mountain: ["MT", "MTS"],
    peak: ["PK", "PKS"],
    hill: ["HLL", "HLLS"],
    volcano: ["VLC"],
    ridge: ["RDGE"],
    valley: ["VAL", "VALS"],
    canyon: ["CNYN"],
    gorge: ["GRGE"],
    glacier: ["GLCR"],
    crater: ["CRTR"],
    plateau: ["PLAT"],
    plain: ["PLN"],
    dune: ["DUNE"],
    cape: ["CAPE", "PT"],
    peninsula: ["PEN"],
    island: ["ISL", "ISLS", "ISLT", "ISLF", "ISLM", "ISLET"],
    beach: ["BCH", "BCHS"],
    desert: ["DSRT", "ERG", "REG"],
    cliff: ["CLF"],
    sinkhole: ["SINK"],
    cave: ["CAVE"],
    rock: ["RK", "RKS"],
    lake: ["LK", "LKS", "LKC", "LKN", "LKI", "LKO"],
    river: ["STM", "STMS", "STMI", "WTRC"],
    waterfall: ["FLLS"],
    bay: ["BAY", "BAYS"],
    gulf: ["GULF"],
    sea: ["SEA"],
    ocean: ["OCN"],
    spring: ["SPNG", "SPNS", "SPNT", "GYSR"],
    reservoir: ["RSV", "RSVI", "RSVT"],
    pond: ["PND", "PNDS", "PNDN"],
    canal: ["CNL", "CNLD", "CNLI", "CNLN"],
    dam: ["DAM", "DAMQ", "DAMSB"],
    harbor: ["HBR", "HBRX", "DCK", "DCKB"],
    reef: ["RF", "RFC", "RFX", "RFSU", "RFU"],
    wetland: ["WTLD", "WTLDI", "BOG", "MGV", "MRSH", "MRSHN", "SWMP"],
    forest: ["FRST", "FRSTF"],
    grove: ["GROVE", "GRVC", "GRVO", "GRVP", "GRVPN"],
    grassland: ["GRSLD"],
    heath: ["HTH"],
    meadow: ["MDW"],
    orchard: ["OCH"],
    scrubland: ["SCRB"],
    tundra: ["TUND"],
    vineyard: ["VIN", "VINS"],
    park: ["PRK"],
    reserve: ["RES", "RESA", "RESF", "RESH", "RESN", "RESP", "RESV", "RESW"],
    region: ["RGN"],
    oasis: ["OAS"],
    field: ["FLD", "FLDI"],
    grazing: ["GRAZ"],
    snowfield: ["SNOW"],
    road: ["RD"],
    railroad: ["RR"],
    trail: ["TRL"],
    bridge: ["BDG", "BDGQ"],
    tunnel: ["TNL", "TNLN", "TNLRD", "TNLRR"],
    airport: ["AIRP"],
    airfield: ["AIRB", "AIRF", "AIRQ"],
    heliport: ["AIRH"],
    port: ["PRT"],
    building: ["BLDG", "BLDA", "BLDO"],
    monument: ["MNMT"],
    church: ["CH"],
    mosque: ["MSQE"],
    school: ["SCH"],
    university: ["UNIV"],
    hospital: ["HSP"],
    hotel: ["HTL"],
    museum: ["MUS"],
    theatre: ["THTR"],
    tower: ["TOWR"],
    castle: ["CSTL"],
    fort: ["FT"],
    ruin: ["RUIN"],
    lighthouse: ["LTHSE"],
    cemetery: ["CMTY"],
    archaeological_site: ["ANS"],
    market: ["MKT"],
    zoo: ["ZOO"],
    farm: ["FRM", "FRMS", "FRMT"]
  }

  @doc """
  Returns the available feature-code group names, sorted.
  """
  def groups, do: @groups |> Map.keys() |> Enum.sort()

  @doc """
  Returns the available feature-class alias names, sorted.
  """
  def classes, do: @classes |> Map.keys() |> Enum.sort()

  @doc """
  Resolves a feature-code group name or raw code to a list of GeoNames codes.

  Atoms are looked up in the taxonomy; strings are treated as raw codes and
  upper-cased. Returns `{:ok, codes}` or `:error`.
  """
  def codes(group) when is_atom(group) and not is_nil(group) do
    case Map.fetch(@groups, group) do
      {:ok, codes} -> {:ok, codes}
      :error -> :error
    end
  end

  def codes(code) when is_binary(code), do: {:ok, [String.upcase(String.trim(code))]}
  def codes(_code), do: :error

  @doc """
  Resolves a feature-class alias name or raw class letter to its class letters.

  Returns `{:ok, classes}` or `:error`.
  """
  def classes(name) when is_atom(name) and not is_nil(name) do
    case Map.fetch(@classes, name) do
      {:ok, classes} -> {:ok, classes}
      :error -> :error
    end
  end

  def classes(letter) when is_binary(letter), do: {:ok, [String.upcase(String.trim(letter))]}
  def classes(_name), do: :error
end
