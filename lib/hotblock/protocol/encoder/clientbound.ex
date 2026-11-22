defmodule Hotblock.Protocol.Encoder.Clientbound do
  # The packets the proxy sends to the client
  alias Hotblock.Packets
  alias Hotblock.Protocol.{Encoder, NBT, Types}

  # Identifies the proxy's boss bar on the client. Any 16 bytes work, as long
  # as every boss bar packet uses the same ones.
  @boss_bar_uuid "hotblockbossbar!"

  # A chat message from the server. The last byte is the overlay flag:
  # false shows it in the chat instead of the action bar
  def system_chat(text) do
    Encoder.encode_packet(Packets.Clientbound.system_chat(), NBT.encode_text(text) <> <<0>>)
  end

  def disconnect(reason) do
    Encoder.encode_packet(Packets.Clientbound.disconnect(), NBT.encode_text(reason))
  end

  def action_bar(text) do
    Encoder.encode_packet(Packets.Clientbound.action_bar(), NBT.encode_text(text))
  end

  def set_title_subtitle(text) do
    Encoder.encode_packet(Packets.Clientbound.set_title_subtitle(), NBT.encode_text(text))
  end

  def set_title_text(text) do
    Encoder.encode_packet(Packets.Clientbound.set_title_text(), NBT.encode_text(text))
  end

  def set_title_time(fade_in, stay, fade_out) do
    Encoder.encode_packet(
      Packets.Clientbound.set_title_time(),
      <<fade_in::32, stay::32, fade_out::32>>
    )
  end

  def game_state_change(reason, value) do
    Encoder.encode_packet(
      Packets.Clientbound.game_state_change(),
      <<reason_code(reason), value::float-32>>
    )
  end

  defp reason_code(:start_raining), do: 1
  defp reason_code(:stop_raining), do: 2
  defp reason_code(:rain_level_change), do: 7
  defp reason_code(:thunder_level_change), do: 8

  # Starting or stopping the rain only changes the state. The levels are what
  # the player sees, and thunder only shows while it is raining.
  def weather(:clear), do: weather(:stop_raining, 0.0, 0.0)
  def weather(:rain), do: weather(:start_raining, 1.0, 0.0)
  def weather(:thunder), do: weather(:start_raining, 1.0, 1.0)

  defp weather(rain_state, rain_level, thunder_level) do
    game_state_change(rain_state, 0.0) <>
      game_state_change(:rain_level_change, rain_level) <>
      game_state_change(:thunder_level_change, thunder_level)
  end

  def boss_bar_add(title, health, color) do
    bar(
      0,
      NBT.encode_text(title) <>
        <<health::float-32>> <>
        Types.encode_varint(color_code(color)) <> Types.encode_varint(0) <> <<0>>
    )
  end

  def boss_bar_remove() do
    bar(1, <<>>)
  end

  def boss_bar_update_health(health) do
    bar(2, <<health::float-32>>)
  end

  def boss_bar_update_title(title) do
    bar(3, NBT.encode_text(title))
  end

  def boss_bar_update_style(color) do
    bar(4, Types.encode_varint(color_code(color)) <> Types.encode_varint(0))
  end

  def sound_effect(name, {x, y, z}) do
    Encoder.encode_packet(
      Packets.Clientbound.sound_effect(),
      Types.encode_varint(0) <>
        Types.encode_string(name) <>
        <<0>> <>
        Types.encode_varint(0) <>
        <<trunc(x * 8)::signed-32, trunc(y * 8)::signed-32, trunc(z * 8)::signed-32>> <>
        <<1.0::float-32, 1.0::float-32>> <> <<0::64>>
    )
  end

  defp bar(action, fields) do
    Encoder.encode_packet(
      Packets.Clientbound.boss_bar(),
      @boss_bar_uuid <> Types.encode_varint(action) <> fields
    )
  end

  defp color_code(:pink), do: 0
  defp color_code(:blue), do: 1
  defp color_code(:red), do: 2
  defp color_code(:green), do: 3
  defp color_code(:yellow), do: 4
  defp color_code(:purple), do: 5
  defp color_code(:white), do: 6
end
