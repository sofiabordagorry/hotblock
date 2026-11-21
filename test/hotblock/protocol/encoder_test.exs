defmodule Hotblock.Protocol.EncoderTest do
  use ExUnit.Case, async: true

  alias Hotblock.Protocol
  alias Hotblock.Protocol.{Encoder, Types}

  describe "encode_frame/1" do
    test "adds the length in front of the frame" do
      assert Encoder.encode_frame(<<0xAA, 0xBB, 0xCC>>) == <<0x03, 0xAA, 0xBB, 0xCC>>
    end

    test "uses more than one byte for a long frame" do
      payload = :binary.copy(<<0xAA>>, 200)

      assert Encoder.encode_frame(payload) == <<0xC8, 0x01>> <> payload
    end

    test "gives back the same frame when read with next_frame" do
      assert Protocol.next_frame(Encoder.encode_frame(<<0xAA, 0xBB>>)) ==
               {:ok, <<0xAA, 0xBB>>, ""}
    end
  end

  describe "encode_packet/2" do
    test "builds a frame with the length, the packet ID and the fields" do
      assert Encoder.encode_packet(0x79, <<0xAA, 0xBB>>) == <<0x03, 0x79, 0xAA, 0xBB>>
    end

    test "encodes the packet ID as a VarInt" do
      # 0x83 does not fit in 7 bits, so the ID takes two bytes
      assert Encoder.encode_packet(0x83, <<0xAA>>) == <<0x03, 0x83, 0x01, 0xAA>>
    end

    test "builds a packet with no fields" do
      assert Encoder.encode_packet(0x00, <<>>) == <<0x01, 0x00>>
    end

    test "gives back the same ID and fields when decoded" do
      for {id, fields} <- [
            {0x00, <<>>},
            {0x79, <<0xAA, 0xBB>>},
            {0x83, :binary.copy(<<0xCC>>, 200)}
          ] do
        assert {:ok, frame, ""} = Protocol.next_frame(Encoder.encode_packet(id, fields))
        assert Types.decode_varint(frame) == {:ok, id, fields}
      end
    end
  end

  describe "system_chat/1" do
    test "builds the full frame: length, ID, NBT text and overlay false" do
      nbt = <<0x0A, 0x08, 0x00, 0x04, "text", 0x00, 0x02, "Hi", 0x00>>

      assert Encoder.system_chat("Hi") == <<0x0F, 0x79>> <> nbt <> <<0x00>>
    end

    test "can be read back with next_frame" do
      assert {:ok, <<0x79, _rest::binary>>, ""} = Protocol.next_frame(Encoder.system_chat("Hi"))
    end
  end

  describe "set_title_time/3" do
    test "builds the frame with fade in, stay and fade out as 32-bit integers" do
      assert Encoder.set_title_time(10, 70, 20) ==
               <<0x0D, 0x73, 10::32, 70::32, 20::32>>
    end
  end

  describe "set_title_text/1" do
    test "builds the frame with the text as NBT" do
      nbt = <<0x0A, 0x08, 0x00, 0x04, "text", 0x00, 0x02, "Hi", 0x00>>

      assert Encoder.set_title_text("Hi") == <<0x0E, 0x72>> <> nbt
    end
  end

  describe "set_title_subtitle/1" do
    test "builds the frame with the text as NBT" do
      nbt = <<0x0A, 0x08, 0x00, 0x04, "text", 0x00, 0x02, "Hi", 0x00>>

      assert Encoder.set_title_subtitle("Hi") == <<0x0E, 0x70>> <> nbt
    end
  end

  describe "action_bar/1" do
    test "builds the frame with the text as NBT" do
      nbt = <<0x0A, 0x08, 0x00, 0x04, "text", 0x00, 0x02, "Hi", 0x00>>

      assert Encoder.action_bar("Hi") == <<0x0E, 0x57>> <> nbt
    end
  end

  # game_state_change (0x26): the reason as a byte and a 32-bit float value
  defp game_state(reason, value), do: <<0x06, 0x26, reason, value::float-32>>

  describe "game_state_change/2" do
    test "builds the frame with the reason and the value" do
      assert Encoder.game_state_change(:rain_level_change, 1.0) ==
               <<0x06, 0x26, 0x07, 0x3F, 0x80, 0x00, 0x00>>
    end

    test "uses the reason codes from minecraft-data" do
      assert Encoder.game_state_change(:start_raining, 0.0) == game_state(1, 0.0)
      assert Encoder.game_state_change(:stop_raining, 0.0) == game_state(2, 0.0)
      assert Encoder.game_state_change(:rain_level_change, 0.5) == game_state(7, 0.5)
      assert Encoder.game_state_change(:thunder_level_change, 0.5) == game_state(8, 0.5)
    end
  end

  describe "weather/1" do
    test "clear stops the rain and sets both levels to 0" do
      assert Encoder.weather(:clear) ==
               game_state(2, 0.0) <> game_state(7, 0.0) <> game_state(8, 0.0)
    end

    test "rain starts the rain with rain level 1 and thunder level 0" do
      assert Encoder.weather(:rain) ==
               game_state(1, 0.0) <> game_state(7, 1.0) <> game_state(8, 0.0)
    end

    test "thunder starts the rain with both levels at 1" do
      assert Encoder.weather(:thunder) ==
               game_state(1, 0.0) <> game_state(7, 1.0) <> game_state(8, 1.0)
    end
  end

  describe "boss_bar_add/3" do
    test "builds the frame with the add action, title, health, color and no dividers or flags" do
      nbt = <<0x0A, 0x08, 0x00, 0x04, "text", 0x00, 0x02, "Hi", 0x00>>

      assert <<0x26, 0x09, _uuid::binary-size(16), 0x00, rest::binary>> =
               Encoder.boss_bar_add("Hi", 0.5, :red)

      assert rest == nbt <> <<0.5::float-32, 0x02, 0x00, 0x00>>
    end

    test "uses the color codes from the protocol" do
      colors = [pink: 0, blue: 1, red: 2, green: 3, yellow: 4, purple: 5, white: 6]

      for {color, code} <- colors do
        frame = Encoder.boss_bar_add("Hi", 1.0, color)
        # The color is followed by dividers and flags, both 0
        assert binary_part(frame, byte_size(frame) - 3, 3) == <<code, 0x00, 0x00>>
      end
    end
  end

  describe "boss_bar_remove/0" do
    test "builds the frame with the remove action" do
      assert <<0x12, 0x09, _uuid::binary-size(16), 0x01>> = Encoder.boss_bar_remove()
    end

    test "every action uses the same bar" do
      frames = [
        Encoder.boss_bar_add("Hi", 1.0, :red),
        Encoder.boss_bar_remove(),
        Encoder.boss_bar_update_health(0.5),
        Encoder.boss_bar_update_title("Hi"),
        Encoder.boss_bar_update_style(:red)
      ]

      uuids = for <<_, 0x09, uuid::binary-size(16), _::binary>> <- frames, do: uuid

      assert length(uuids) == 5
      assert length(Enum.uniq(uuids)) == 1
    end
  end

  describe "boss_bar_update_health/1" do
    test "builds the frame with the update health action and the health" do
      assert <<0x16, 0x09, _uuid::binary-size(16), 0x02, 0.5::float-32>> =
               Encoder.boss_bar_update_health(0.5)
    end
  end

  describe "boss_bar_update_title/1" do
    test "builds the frame with the update title action and the title as NBT" do
      nbt = <<0x0A, 0x08, 0x00, 0x04, "text", 0x00, 0x02, "Hi", 0x00>>

      assert <<0x1F, 0x09, _uuid::binary-size(16), 0x03, rest::binary>> =
               Encoder.boss_bar_update_title("Hi")

      assert rest == nbt
    end
  end

  describe "boss_bar_update_style/1" do
    test "builds the frame with the update style action, the color and no dividers" do
      assert <<0x14, 0x09, _uuid::binary-size(16), 0x04, 0x02, 0x00>> =
               Encoder.boss_bar_update_style(:red)
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

      assert Encoder.sound_effect(name, {1.5, 64.0, -2.25}) == <<0x40, 0x75>> <> fields
    end

    test "stores each coordinate multiplied by 8, without the decimals" do
      frame = Encoder.sound_effect("minecraft:block.note_block.pling", {10.9, -0.2, 100.0})

      # The coordinates are followed by volume, pitch and seed (16 bytes)
      coordinates = binary_part(frame, byte_size(frame) - 28, 12)

      assert coordinates == <<87::signed-32, -1::signed-32, 800::signed-32>>
    end
  end

  describe "chat_command/1" do
    test "builds the serverbound frame with the command as a string" do
      assert Encoder.chat_command("time set day") == <<0x0E, 0x07, 0x0C, "time set day">>
    end
  end
end
