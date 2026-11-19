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
end
