# This project exists to exercise GeoData as an external dependency, so every
# test here is an integration test; `mix test` in this directory runs the
# offline subset. Tests tagged `:integration` need the network or another
# external service and are excluded unless you opt in:
#
#     mix test --include integration
#
# Tests tagged `:postgres` need a local PostgreSQL (see README) and are excluded
# unless you opt in:
#
#     mix test --include postgres
#
ExUnit.start(exclude: [:integration, :postgres])
