defmodule Hotblock.Effects.EntityWatchTest do
  use ExUnit.Case, async: true

  alias Hotblock.Effects.EntityWatch
  alias Hotblock.Protocol.Encoder

  @player {0.0, 64.0, 0.0}

  # A watch that follows zombies within 10 blocks, with one zombie (entity 42)
  # at the given position
  defp zombie_at(position) do
    {_reply, watch} = EntityWatch.watch(EntityWatch.new(), "zombie", 10)
    EntityWatch.track(watch, {:spawn, 42, 150, position})
  end

  defp alert(text) do
    Encoder.action_bar(text) <> Encoder.sound_effect("minecraft:block.note_block.pling", @player)
  end

  describe "track/2" do
    test "adds a spawned entity with its type name" do
      watch = EntityWatch.track(EntityWatch.new(), {:spawn, 42, 150, {1.0, 64.0, 0.0}})

      assert watch.entities == %{42 => %{type: "zombie", position: {1.0, 64.0, 0.0}}}
    end

    test "ignores an entity type that is not in minecraft-data" do
      watch = EntityWatch.track(EntityWatch.new(), {:spawn, 42, 10_000, {1.0, 64.0, 0.0}})

      assert watch.entities == %{}
    end

    test "adds a relative move to the position" do
      watch =
        EntityWatch.new()
        |> EntityWatch.track({:spawn, 42, 150, {1.0, 64.0, 0.0}})
        |> EntityWatch.track({:move, 42, {0.5, -1.0, 2.0}})

      assert watch.entities[42].position == {1.5, 63.0, 2.0}
    end

    test "ignores a move of an entity it does not know" do
      watch = EntityWatch.track(EntityWatch.new(), {:move, 42, {0.5, -1.0, 2.0}})

      assert watch.entities == %{}
    end

    test "replaces the position on a teleport" do
      watch =
        EntityWatch.new()
        |> EntityWatch.track({:spawn, 42, 150, {1.0, 64.0, 0.0}})
        |> EntityWatch.track({:teleport, 42, {100.0, 70.0, -5.0}})

      assert watch.entities[42].position == {100.0, 70.0, -5.0}
    end

    test "removes entities" do
      watch =
        EntityWatch.new()
        |> EntityWatch.track({:spawn, 42, 150, {1.0, 64.0, 0.0}})
        |> EntityWatch.track({:spawn, 43, 32, {2.0, 64.0, 0.0}})
        |> EntityWatch.track({:spawn, 44, 30, {3.0, 64.0, 0.0}})
        |> EntityWatch.track({:remove, [42, 44]})

      assert Map.keys(watch.entities) == [43]
    end
  end

  describe "watch/3" do
    test "starts watching a known entity and confirms it" do
      {reply, watch} = EntityWatch.watch(EntityWatch.new(), "zombie", 10)

      assert reply == Encoder.system_chat("Watching zombie within 10 blocks")
      assert watch.watches == %{"zombie" => 10}
    end

    test "replies with a chat error for an unknown entity" do
      {reply, watch} = EntityWatch.watch(EntityWatch.new(), "dragon", 10)

      assert reply == Encoder.system_chat("Unknown entity: dragon")
      assert watch == EntityWatch.new()
    end
  end

  describe "unwatch/2" do
    test "stops watching an entity and confirms it" do
      {_reply, watch} = EntityWatch.watch(EntityWatch.new(), "zombie", 10)
      {reply, watch} = EntityWatch.unwatch(watch, "zombie")

      assert reply == Encoder.system_chat("Stopped watching zombie")
      assert watch.watches == %{}
    end

    test "says so when the entity was not being watched" do
      {reply, _watch} = EntityWatch.unwatch(EntityWatch.new(), "zombie")

      assert reply == Encoder.system_chat("You are not watching zombie")
    end
  end

  describe "alerts/3" do
    test "warns with an action bar and a sound when a watched entity is within the radius" do
      {packets, _watch} = EntityWatch.alerts(zombie_at({3.0, 64.0, 0.0}), @player, 0)

      assert packets == alert("zombie 3 blocks away!")
    end

    test "uses the distance in 3D, rounded" do
      # 2 blocks on x, 1 down and 2 on z is 3 blocks away; 0.4 more rounds down
      {packets, _watch} = EntityWatch.alerts(zombie_at({2.0, 63.0, 2.4}), @player, 0)

      assert packets == alert("zombie 3 blocks away!")
    end

    test "says block, not blocks, for 1" do
      {packets, _watch} = EntityWatch.alerts(zombie_at({1.0, 64.0, 0.0}), @player, 0)

      assert packets == alert("zombie 1 block away!")
    end

    test "warns when the entity is exactly at the radius" do
      {packets, _watch} = EntityWatch.alerts(zombie_at({10.0, 64.0, 0.0}), @player, 0)

      assert packets == alert("zombie 10 blocks away!")
    end

    test "does nothing when the entity is outside the radius" do
      assert {<<>>, _watch} = EntityWatch.alerts(zombie_at({11.0, 64.0, 0.0}), @player, 0)
    end

    test "does nothing for entity types that are not watched" do
      {_reply, watch} = EntityWatch.watch(EntityWatch.new(), "creeper", 10)
      watch = EntityWatch.track(watch, {:spawn, 42, 150, {3.0, 64.0, 0.0}})

      assert {<<>>, _watch} = EntityWatch.alerts(watch, @player, 0)
    end

    test "does nothing while the player position is not known" do
      assert {<<>>, _watch} = EntityWatch.alerts(zombie_at({3.0, 64.0, 0.0}), nil, 0)
    end

    test "warns once per entity type, about the closest one" do
      watch =
        zombie_at({8.0, 64.0, 0.0})
        |> EntityWatch.track({:spawn, 43, 150, {0.0, 64.0, 4.0}})

      {packets, _watch} = EntityWatch.alerts(watch, @player, 0)

      assert packets == alert("zombie 4 blocks away!")
    end

    test "warns about each watched type, in alphabetical order" do
      {_reply, watch} = EntityWatch.watch(zombie_at({3.0, 64.0, 0.0}), "creeper", 10)
      watch = EntityWatch.track(watch, {:spawn, 43, 32, {5.0, 64.0, 0.0}})

      {packets, _watch} = EntityWatch.alerts(watch, @player, 0)

      assert packets == alert("creeper 5 blocks away!") <> alert("zombie 3 blocks away!")
    end

    test "waits 5 seconds before warning again about the same type" do
      {_packets, watch} = EntityWatch.alerts(zombie_at({3.0, 64.0, 0.0}), @player, 1_000)

      assert {<<>>, watch} = EntityWatch.alerts(watch, @player, 5_999)
      assert {packets, _watch} = EntityWatch.alerts(watch, @player, 6_000)
      assert packets == alert("zombie 3 blocks away!")
    end
  end
end
