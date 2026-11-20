defmodule Hotblock.Protocol.Encoder do
  # Builds the frames the proxy sends: forwarded frames and its own packets
  alias Hotblock.Packets
  alias Hotblock.Protocol.{NBT, Types}

  # A frame is the length of its content as a VarInt, followed by the content
  def encode_frame(frame) do
    Types.encode_varint(byte_size(frame)) <> frame
  end

  # A packet is a frame whose content starts with the packet ID as a VarInt
  def encode_packet(id, fields) do
    encode_frame(Types.encode_varint(id) <> fields)
  end

  # A chat message from the server. The last byte is the overlay flag:
  # false shows it in the chat instead of the action bar
  def system_chat(text) do
    encode_packet(Packets.system_chat(), NBT.encode_text(text) <> <<0>>)
  end

  def action_bar(text) do
    encode_packet(Packets.action_bar(), NBT.encode_text(text))
  end

  def set_title_subtitle(text) do
    encode_packet(Packets.set_title_subtitle(), NBT.encode_text(text))
  end

  def set_title_text(text) do
    encode_packet(Packets.set_title_text(), NBT.encode_text(text))
  end

  def set_title_time(fade_in, stay, fade_out) do
    encode_packet(Packets.set_title_time(), <<fade_in::32, stay::32, fade_out::32>>)
  end

  def game_state_change(reason, value) do
    encode_packet(Packets.game_state_change(), <<reason_code(reason), value::float-32>>)
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
end
