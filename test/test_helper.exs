# Tests that reach the network or another external service are tagged
# `:integration` and excluded here, so the default `mix test` stays fast and
# offline. Run them explicitly with `mix test --include integration`.
#
# The consumer-side integration suite lives in its own Mix project under
# `integration/`; run it with `mix test.integration`.
ExUnit.start(exclude: [:integration])
