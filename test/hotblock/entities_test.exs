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
end
