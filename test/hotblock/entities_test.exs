defmodule Hotblock.EntitiesTest do
  use ExUnit.Case, async: true

  alias Hotblock.Entities

  describe "name/1" do
    test "returns the name of an entity type id from minecraft-data" do
      assert Entities.name(150) == "zombie"
      assert Entities.name(32) == "creeper"
    end

    test "returns nil for an unknown id" do
      assert Entities.name(10_000) == nil
    end
  end

  describe "known?/1" do
    test "is true for entity names in minecraft-data" do
      assert Entities.known?("zombie")
      assert Entities.known?("creeper")
    end

    test "is false for anything else" do
      refute Entities.known?("dragon")
      refute Entities.known?("")
      # The name is checked without the namespace
      refute Entities.known?("minecraft:zombie")
    end
  end

  describe "spawnable/0" do
    test "has the mobs from minecraft-data, with their display name and category" do
      spawnable = Entities.spawnable()

      assert %{name: "zombie", display_name: "Zombie", category: :hostile} in spawnable
      assert %{name: "pig", display_name: "Pig", category: :passive} in spawnable
    end

    test "has no entities that are not mobs" do
      names = Enum.map(Entities.spawnable(), & &1.name)

      refute "arrow" in names
      refute "oak_boat" in names
    end

    test "is sorted by display name" do
      display_names = Enum.map(Entities.spawnable(), & &1.display_name)

      assert display_names == Enum.sort(display_names)
    end
  end

  describe "category/1" do
    test "is :hostile, :passive or :other" do
      assert Entities.category("zombie") == :hostile
      assert Entities.category("pig") == :passive
      assert Entities.category("arrow") == :other
      assert Entities.category("not_an_entity") == :other
    end
  end
end
