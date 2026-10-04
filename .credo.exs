# Credo configuration.

%{
  configs: [
    %{
      name: "default",
      strict: true,
      files: %{
        included: ["lib/", "test/"],
        excluded: ["deps/", "_build/"]
      },
      checks: [
        {Credo.Check.Design.AliasUsage, false},
        {Credo.Check.Readability.AliasOrder, false},
        {Credo.Check.Refactor.Nesting, false}
      ]
    }
  ]
}
