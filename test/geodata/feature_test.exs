defmodule GeoData.FeatureTest do
  use ExUnit.Case, async: true

  alias GeoData.Feature

  doctest GeoData.Feature

  describe "groups/0" do
    test "returns sorted, unique group names" do
      groups = Feature.groups()
      assert groups == Enum.sort(Enum.uniq(groups))
      assert :mountain in groups
      assert :lake in groups
      assert :airport in groups
    end

    test "every group is non-empty with well-formed, unique codes" do
      Enum.each(Feature.groups(), fn group ->
        assert {:ok, codes} = Feature.codes(group)
        assert match?([_ | _], codes)
        assert codes == Enum.uniq(codes)

        Enum.each(codes, fn code ->
          assert is_binary(code)
          assert code == String.upcase(code)
          assert code =~ ~r/^[A-Z0-9]{2,6}$/
        end)
      end)
    end
  end

  describe "classes/0" do
    test "returns sorted class aliases mapping to a single letter" do
      classes = Feature.classes()
      assert classes == Enum.sort(Enum.uniq(classes))
      assert :landforms in classes

      Enum.each(classes, fn name ->
        assert {:ok, [letter]} = Feature.classes(name)
        assert letter =~ ~r/^[A-Z]$/
      end)
    end

    test "covers all nine GeoNames feature classes" do
      letters =
        Feature.classes()
        |> Enum.map(&Feature.classes/1)
        |> Enum.map(fn {:ok, [letter]} -> letter end)
        |> Enum.sort()

      assert letters == ~w(A H L P R S T U V)
    end
  end

  describe "codes/1 and classes/1" do
    test "accept atoms and raw strings" do
      assert Feature.codes(:mountain) == {:ok, ["MT", "MTS"]}
      assert Feature.codes(" mt ") == {:ok, ["MT"]}
      assert Feature.classes(:landforms) == {:ok, ["T"]}
      assert Feature.classes(" t ") == {:ok, ["T"]}
    end

    test "return :error for unknown names and invalid input" do
      assert Feature.codes(:bogus) == :error
      assert Feature.classes(:bogus) == :error
      assert Feature.codes(nil) == :error
      assert Feature.classes(123) == :error
    end
  end
end
