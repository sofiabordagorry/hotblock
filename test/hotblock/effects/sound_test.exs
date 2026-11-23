defmodule Hotblock.Effects.SoundTest do
  use ExUnit.Case, async: true

  alias Hotblock.Effects.Sound
  alias Hotblock.Protocol.Encoder.Clientbound

  describe "known?/1" do
    test "is true for sounds in minecraft-data" do
      assert Sound.known?("entity.player.levelup")
      assert Sound.known?("block.note_block.pling")
    end

    test "is false for anything else" do
      refute Sound.known?("entity.player.dance")
      refute Sound.known?("")
      # The name is checked without the namespace
      refute Sound.known?("minecraft:entity.player.levelup")
    end
  end

  describe "packets/2" do
    @position {1.5, 64.0, -2.25}

    test "plays a known sound at the position" do
      assert Sound.packets("entity.player.levelup", @position) ==
               Clientbound.sound_effect("minecraft:entity.player.levelup", @position)
    end

    test "replies with a chat error for an unknown sound" do
      assert Sound.packets("entity.player.dance", @position) ==
               Clientbound.system_chat("Unknown sound: entity.player.dance")
    end

    test "replies with a chat error when the position is not known yet" do
      assert Sound.packets("entity.player.levelup", nil) ==
               Clientbound.system_chat("Your position is not known yet, move a bit and try again")
    end
  end

  describe "names/0" do
    test "has the sounds from minecraft-data, sorted" do
      names = Sound.names()

      assert "entity.creeper.primed" in names
      assert names == Enum.sort(names)
    end
  end
end
