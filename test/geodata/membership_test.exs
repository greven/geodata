defmodule GeoData.MembershipTest do
  use ExUnit.Case, async: true
  doctest GeoData.Membership

  alias GeoData.Membership

  describe "groups/1" do
    test "returns immediate unions and M49 groupings" do
      assert {:ok, groups} = Membership.groups(:PT)

      assert :EU in groups
      assert :EZ in groups
      assert :UN in groups
      assert :"039" in groups
    end

    test "reflects that Norway is not in the EU" do
      assert {:ok, groups} = Membership.groups(:NO)

      refute :EU in groups
      refute :EZ in groups
      assert :UN in groups
    end

    test "returns an error for an unknown territory" do
      assert {:error, _} = Membership.groups(:ZZ)
    end
  end

  describe "member_of?/2" do
    test "checks membership" do
      assert Membership.member_of?(:PT, :EU)
      assert Membership.member_of?(:PT, :EZ)
      assert Membership.member_of?(:NO, :UN)
    end

    test "is false for non-members and unknown groups" do
      refute Membership.member_of?(:NO, :EU)
      refute Membership.member_of?(:CH, :EZ)
      refute Membership.member_of?(:PT, :NATO)
    end
  end

  describe "group_name/2" do
    test "resolves M49 grouping names" do
      assert {:ok, "Southern Europe"} = Membership.group_name(:"039")
      assert {:ok, "Northern Europe"} = Membership.group_name(:"154")
    end

    test "resolves union names" do
      assert {:ok, "European Union"} = Membership.group_name(:EU)
    end

    test "accepts a locale" do
      assert {:ok, "European Union"} = Membership.group_name(:EU, locale: :en)
    end
  end
end
