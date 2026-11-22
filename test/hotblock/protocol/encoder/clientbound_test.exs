defmodule Hotblock.Protocol.Encoder.ClientboundTest do
  use ExUnit.Case, async: true

  alias Hotblock.Protocol
  alias Hotblock.Protocol.Encoder.Clientbound

  describe "system_chat/1" do
    test "builds the full frame: length, ID, NBT text and overlay false" do
      nbt = <<0x0A, 0x08, 0x00, 0x04, "text", 0x00, 0x02, "Hi", 0x00>>

      assert Clientbound.system_chat("Hi") == <<0x0F, 0x79>> <> nbt <> <<0x00>>
    end

    test "can be read back with next_frame" do
      assert {:ok, <<0x79, _rest::binary>>, ""} =
               Protocol.next_frame(Clientbound.system_chat("Hi"))
    end
  end

  describe "set_title_time/3" do
    test "builds the frame with fade in, stay and fade out as 32-bit integers" do
      assert Clientbound.set_title_time(10, 70, 20) ==
               <<0x0D, 0x73, 10::32, 70::32, 20::32>>
    end
  end

  describe "set_title_text/1" do
    test "builds the frame with the text as NBT" do
      nbt = <<0x0A, 0x08, 0x00, 0x04, "text", 0x00, 0x02, "Hi", 0x00>>

      assert Clientbound.set_title_text("Hi") == <<0x0E, 0x72>> <> nbt
    end
  end

  describe "set_title_subtitle/1" do
    test "builds the frame with the text as NBT" do
      nbt = <<0x0A, 0x08, 0x00, 0x04, "text", 0x00, 0x02, "Hi", 0x00>>

      assert Clientbound.set_title_subtitle("Hi") == <<0x0E, 0x70>> <> nbt
    end
  end

  describe "action_bar/1" do
    test "builds the frame with the text as NBT" do
      nbt = <<0x0A, 0x08, 0x00, 0x04, "text", 0x00, 0x02, "Hi", 0x00>>

      assert Clientbound.action_bar("Hi") == <<0x0E, 0x57>> <> nbt
    end
  end

  # game_state_change (0x26): the reason as a byte and a 32-bit float value
  defp game_state(reason, value), do: <<0x06, 0x26, reason, value::float-32>>

  describe "game_state_change/2" do
    test "builds the frame with the reason and the value" do
      assert Clientbound.game_state_change(:rain_level_change, 1.0) ==
               <<0x06, 0x26, 0x07, 0x3F, 0x80, 0x00, 0x00>>
    end

    test "uses the reason codes from minecraft-data" do
      assert Clientbound.game_state_change(:start_raining, 0.0) == game_state(1, 0.0)
      assert Clientbound.game_state_change(:stop_raining, 0.0) == game_state(2, 0.0)
      assert Clientbound.game_state_change(:rain_level_change, 0.5) == game_state(7, 0.5)
      assert Clientbound.game_state_change(:thunder_level_change, 0.5) == game_state(8, 0.5)
    end
  end

  describe "weather/1" do
    test "clear stops the rain and sets both levels to 0" do
      assert Clientbound.weather(:clear) ==
               game_state(2, 0.0) <> game_state(7, 0.0) <> game_state(8, 0.0)
    end

    test "rain starts the rain with rain level 1 and thunder level 0" do
      assert Clientbound.weather(:rain) ==
               game_state(1, 0.0) <> game_state(7, 1.0) <> game_state(8, 0.0)
    end

    test "thunder starts the rain with both levels at 1" do
      assert Clientbound.weather(:thunder) ==
               game_state(1, 0.0) <> game_state(7, 1.0) <> game_state(8, 1.0)
    end
  end

  describe "boss_bar_add/3" do
    test "builds the frame with the add action, title, health, color and no dividers or flags" do
      nbt = <<0x0A, 0x08, 0x00, 0x04, "text", 0x00, 0x02, "Hi", 0x00>>

      assert <<0x26, 0x09, _uuid::binary-size(16), 0x00, rest::binary>> =
               Clientbound.boss_bar_add("Hi", 0.5, :red)

      assert rest == nbt <> <<0.5::float-32, 0x02, 0x00, 0x00>>
    end

    test "uses the color codes from the protocol" do
      colors = [pink: 0, blue: 1, red: 2, green: 3, yellow: 4, purple: 5, white: 6]

      for {color, code} <- colors do
        frame = Clientbound.boss_bar_add("Hi", 1.0, color)
        # The color is followed by dividers and flags, both 0
        assert binary_part(frame, byte_size(frame) - 3, 3) == <<code, 0x00, 0x00>>
      end
    end
  end

  describe "boss_bar_remove/0" do
    test "builds the frame with the remove action" do
      assert <<0x12, 0x09, _uuid::binary-size(16), 0x01>> = Clientbound.boss_bar_remove()
    end

    test "every action uses the same bar" do
      frames = [
        Clientbound.boss_bar_add("Hi", 1.0, :red),
        Clientbound.boss_bar_remove(),
        Clientbound.boss_bar_update_health(0.5),
        Clientbound.boss_bar_update_title("Hi"),
        Clientbound.boss_bar_update_style(:red)
      ]

      uuids = for <<_, 0x09, uuid::binary-size(16), _::binary>> <- frames, do: uuid

      assert length(uuids) == 5
      assert length(Enum.uniq(uuids)) == 1
    end
  end

  describe "boss_bar_update_health/1" do
    test "builds the frame with the update health action and the health" do
      assert <<0x16, 0x09, _uuid::binary-size(16), 0x02, 0.5::float-32>> =
               Clientbound.boss_bar_update_health(0.5)
    end
  end

  describe "boss_bar_update_title/1" do
    test "builds the frame with the update title action and the title as NBT" do
      nbt = <<0x0A, 0x08, 0x00, 0x04, "text", 0x00, 0x02, "Hi", 0x00>>

      assert <<0x1F, 0x09, _uuid::binary-size(16), 0x03, rest::binary>> =
               Clientbound.boss_bar_update_title("Hi")

      assert rest == nbt
    end
  end

  describe "boss_bar_update_style/1" do
    test "builds the frame with the update style action, the color and no dividers" do
      assert <<0x14, 0x09, _uuid::binary-size(16), 0x04, 0x02, 0x00>> =
               Clientbound.boss_bar_update_style(:red)
    end
  end

  describe "sound_effect/2" do
    test "builds the frame with the sound by name, the category and the position" do
      name = "minecraft:entity.player.levelup"

      fields =
        <<0x00>> <>
          <<0x1F>> <>
          name <>
          <<0x00>> <>
          <<0x00>> <>
          <<12::signed-32, 512::signed-32, -18::signed-32>> <>
          <<1.0::float-32, 1.0::float-32>> <>
          <<0::64>>

      assert Clientbound.sound_effect(name, {1.5, 64.0, -2.25}) == <<0x40, 0x75>> <> fields
    end

    test "stores each coordinate multiplied by 8, without the decimals" do
      frame = Clientbound.sound_effect("minecraft:block.note_block.pling", {10.9, -0.2, 100.0})

      # The coordinates are followed by volume, pitch and seed (16 bytes)
      coordinates = binary_part(frame, byte_size(frame) - 28, 12)

      assert coordinates == <<87::signed-32, -1::signed-32, 800::signed-32>>
    end
  end

  describe "disconnect/1" do
    test "is packet 0x20 with the reason as a text component" do
      nbt = Hotblock.Protocol.NBT.encode_text("Bye")
      assert Clientbound.disconnect("Bye") == <<byte_size(nbt) + 1, 0x20>> <> nbt
    end
  end
end
