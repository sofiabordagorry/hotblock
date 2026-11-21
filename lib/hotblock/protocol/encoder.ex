defmodule Hotblock.Protocol.Encoder do
  # Builds frames: forwarded frames and the proxy's own packets. The packets
  # themselves are in Encoder.Clientbound and Encoder.Serverbound.
  alias Hotblock.Protocol.Types

  # A frame is the length of its content as a VarInt, followed by the content
  def encode_frame(frame) do
    Types.encode_varint(byte_size(frame)) <> frame
  end

  # A packet is a frame whose content starts with the packet ID as a VarInt
  def encode_packet(id, fields) do
    encode_frame(Types.encode_varint(id) <> fields)
  end
end
