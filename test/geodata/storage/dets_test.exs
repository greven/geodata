defmodule GeoData.Storage.DETS.EagerTest do
  use GeoData.DETSStorageTests, memory_mode: :eager
end

defmodule GeoData.Storage.DETS.LazyTest do
  use GeoData.DETSStorageTests, memory_mode: :lazy
end
