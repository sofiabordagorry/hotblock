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

  def set_title_text(text) do
    encode_packet(Packets.set_title_text(), NBT.encode_text(text))
  end

  def set_title_times(fade_in, stay, fade_out) do
    encode_packet(Packets.set_title_times(), <<fade_in::32, stay::32, fade_out::32>>)
  end
end
