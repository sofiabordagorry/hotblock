defmodule Hotblock.Effects.SpawnTest do
  use ExUnit.Case, async: true

  alias Hotblock.Effects.Spawn
  alias Hotblock.Protocol.Encoder

  @player {0.0, 64.0, 0.0}

  defp assert_position({x, y, z}, {expected_x, expected_y, expected_z}) do
    assert_in_delta x, expected_x, 0.0001
    assert_in_delta y, expected_y, 0.0001
    assert_in_delta z, expected_z, 0.0001
  end

  describe "position/4" do
    # In Minecraft, yaw 0 faces south (+z), 90 west (-x), 180 north (-z)
    # and -90 east (+x)
    test "behind: facing south, it is north" do
      assert_position(Spawn.position(@player, 0.0, 3, :behind), {0.0, 64.0, -3.0})
    end

    test "behind: facing west, it is east" do
      assert_position(Spawn.position(@player, 90.0, 3, :behind), {3.0, 64.0, 0.0})
    end

    test "behind: facing north, it is south" do
      assert_position(Spawn.position(@player, 180.0, 3, :behind), {0.0, 64.0, 3.0})
    end

    test "behind: facing east, it is west" do
      assert_position(Spawn.position(@player, -90.0, 3, :behind), {-3.0, 64.0, 0.0})
    end

    test "front is where the player looks" do
      assert_position(Spawn.position(@player, 0.0, 3, :front), {0.0, 64.0, 3.0})
    end

    test "right and left: facing south, right is west and left is east" do
      assert_position(Spawn.position(@player, 0.0, 3, :right), {-3.0, 64.0, 0.0})
      assert_position(Spawn.position(@player, 0.0, 3, :left), {3.0, 64.0, 0.0})
    end

    test "works for any yaw, like one between two directions or above 360" do
      # 45 is between south and west, so behind is between north and east
      assert_position(Spawn.position(@player, 45.0, 2, :behind), {1.4142, 64.0, -1.4142})
      assert_position(Spawn.position(@player, 450.0, 3, :behind), {3.0, 64.0, 0.0})
    end

    test "starts from the player position and keeps the height" do
      assert_position(Spawn.position({10.0, 70.0, -5.0}, 0.0, 5, :behind), {10.0, 70.0, -10.0})
    end
  end

  describe "packets/5" do
    test "sends the summon command to the server for a known entity" do
      assert Spawn.packets("zombie", 3, :behind, @player, 0.0) ==
               {:server, Encoder.chat_command("summon minecraft:zombie 0.00 64.00 -3.00")}
    end

    test "uses the direction" do
      assert Spawn.packets("zombie", 5, :front, @player, 0.0) ==
               {:server, Encoder.chat_command("summon minecraft:zombie 0.00 64.00 5.00")}
    end

    test "replies with a chat error for an unknown entity" do
      assert Spawn.packets("dragon", 3, :behind, @player, 0.0) ==
               {:client, Encoder.system_chat("Unknown entity: dragon")}
    end

    test "replies with a chat error while the position or the yaw are not known" do
      error =
        {:client, Encoder.system_chat("Your position is not known yet, move a bit and try again")}

      assert Spawn.packets("zombie", 3, :behind, nil, 0.0) == error
      assert Spawn.packets("zombie", 3, :behind, @player, nil) == error
    end
  end
end
