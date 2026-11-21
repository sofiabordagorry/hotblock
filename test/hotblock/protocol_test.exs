defmodule Hotblock.ProtocolTest do
  use ExUnit.Case, async: true

  alias Hotblock.Protocol

  describe "next_frame/1" do
    test "returns a complete frame and an empty rest" do
      assert Protocol.next_frame(<<0x03, 0xAA, 0xBB, 0xCC>>) == {:ok, <<0xAA, 0xBB, 0xCC>>, ""}
    end

    test "returns the bytes after the frame as rest" do
      assert Protocol.next_frame(<<0x01, 0xAA, 0x02, 0xBB>>) == {:ok, <<0xAA>>, <<0x02, 0xBB>>}
    end

    test "reads a length that takes more than one byte" do
      payload = :binary.copy(<<0xAA>>, 200)

      assert Protocol.next_frame(<<0xC8, 0x01>> <> payload) == {:ok, payload, ""}
    end

    test "returns :incomplete for an empty buffer" do
      assert Protocol.next_frame(<<>>) == :incomplete
    end

    test "returns :incomplete when the length is cut in the middle" do
      assert Protocol.next_frame(<<0xC8>>) == :incomplete
    end

    test "returns :incomplete when the payload is not complete yet" do
      assert Protocol.next_frame(<<0x03, 0xAA, 0xBB>>) == :incomplete
    end

    test "accepts the maximum frame length" do
      # 2_097_151 = 2^21 - 1, the largest length Minecraft allows
      assert Protocol.next_frame(<<0xFF, 0xFF, 0x7F>>) == :incomplete
    end

    test "returns an error when the length is too long" do
      # 2_097_152 = 2^21
      assert Protocol.next_frame(<<0x80, 0x80, 0x80, 0x01>>) ==
               {:error, :invalid_frame_length}
    end

    test "returns an error when the length is negative" do
      assert Protocol.next_frame(<<0xFF, 0xFF, 0xFF, 0xFF, 0x0F>>) ==
               {:error, :invalid_frame_length}
    end

    test "returns the varint error when the length is longer than 5 bytes" do
      assert Protocol.next_frame(<<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01>>) ==
               {:error, :varint_too_long}
    end
  end

  describe "split_frames/1" do
    # Three frames back to back. The last one has a 200-byte payload,
    # so its length takes two bytes and can be split in the middle.
    @frames [<<0xAA>>, <<0xBB, 0xCC, 0xDD>>, :binary.copy(<<0xEE>>, 200)]
    @stream <<0x01, 0xAA>> <>
              <<0x03, 0xBB, 0xCC, 0xDD>> <>
              <<0xC8, 0x01>> <> :binary.copy(<<0xEE>>, 200)

    test "returns no frames for an empty buffer" do
      assert Protocol.split_frames(<<>>) == {:ok, [], ""}
    end

    test "returns several frames from one read" do
      assert Protocol.split_frames(@stream) == {:ok, @frames, ""}
    end

    test "keeps an incomplete frame as rest" do
      assert Protocol.split_frames(<<0x01, 0xAA, 0x03, 0xBB>>) ==
               {:ok, [<<0xAA>>], <<0x03, 0xBB>>}
    end

    test "returns an error when a frame is invalid" do
      assert Protocol.split_frames(<<0x01, 0xAA, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F>>) ==
               {:error, :invalid_frame_length}
    end

    test "gives the same frames when the stream is split at every byte position" do
      for i <- 0..byte_size(@stream) do
        first = binary_part(@stream, 0, i)
        second = binary_part(@stream, i, byte_size(@stream) - i)

        assert feed([first, second]) == @frames, "failed when splitting at byte #{i}"
      end
    end

    test "gives the same frames when the stream arrives one byte at a time" do
      bytes = for <<byte <- @stream>>, do: <<byte>>

      assert feed(bytes) == @frames
    end
  end

  # Handshake payload (without the packet ID) for protocol 775 connecting to
  # localhost:25565. The intent goes at the end and changes per test.
  @handshake_fields <<0x87, 0x06>> <> <<0x09, "localhost">> <> <<0x63, 0xDD>>

  describe "decode_handshake/1" do
    test "decodes every field" do
      assert Protocol.decode_handshake(@handshake_fields <> <<0x02>>) ==
               {:ok,
                %{
                  protocol_version: 775,
                  server_address: "localhost",
                  server_port: 25565,
                  intent: 2
                }}
    end

    test "returns an error when the payload is cut" do
      assert Protocol.decode_handshake(@handshake_fields) == {:error, :invalid_handshake}

      assert Protocol.decode_handshake(<<0x87, 0x06, 0x09, "local">>) ==
               {:error, :invalid_handshake}
    end

    test "returns an error when there are bytes after the intent" do
      assert Protocol.decode_handshake(@handshake_fields <> <<0x02, 0xAA>>) ==
               {:error, :invalid_handshake}
    end
  end

  describe "next_state/2" do
    test "goes from handshaking to status when the intent is 1" do
      assert Protocol.next_state(:handshaking, <<0x00>> <> @handshake_fields <> <<0x01>>) ==
               {:ok, :status}
    end

    test "goes from handshaking to login when the intent is 2" do
      assert Protocol.next_state(:handshaking, <<0x00>> <> @handshake_fields <> <<0x02>>) ==
               {:ok, :login}
    end

    test "goes from handshaking to login when the intent is 3 (transfer)" do
      assert Protocol.next_state(:handshaking, <<0x00>> <> @handshake_fields <> <<0x03>>) ==
               {:ok, :login}
    end

    test "goes from login to configuration on Login Acknowledged" do
      assert Protocol.next_state(:login, <<0x03>>) == {:ok, :configuration}
    end

    test "goes from configuration to play on Acknowledge Finish Configuration" do
      assert Protocol.next_state(:configuration, <<0x03>>) == {:ok, :play}
    end

    test "keeps the state for other packets" do
      # Login Start, in login
      assert Protocol.next_state(:login, <<0x00, 0x05, "steve">>) == {:ok, :login}
      # Client Information, in configuration
      assert Protocol.next_state(:configuration, <<0x00, 0xAA>>) == {:ok, :configuration}
    end

    test "only uses ID 0x03 in the state where it means a change" do
      assert Protocol.next_state(:status, <<0x03>>) == {:ok, :status}
      assert Protocol.next_state(:play, <<0x03>>) == {:ok, :play}
    end

    test "returns an error for an invalid handshake" do
      assert Protocol.next_state(:handshaking, <<0x00>> <> @handshake_fields) ==
               {:error, :invalid_handshake}
    end

    test "returns an error for an unknown intent" do
      assert Protocol.next_state(:handshaking, <<0x00>> <> @handshake_fields <> <<0x04>>) ==
               {:error, :invalid_intent}
    end
  end

  describe "decode_command/2" do
    # chat_command (0x07) followed by the command, without the slash
    test "returns the command of a chat_command in play" do
      assert Protocol.decode_command(:play, <<0x07, 0x05, "hello">>) == {:ok, "hello"}
    end

    test "returns the arguments as part of the command" do
      assert Protocol.decode_command(:play, <<0x07, 0x0B, "fx title Hi">>) ==
               {:ok, "fx title Hi"}
    end

    test "returns :error outside play" do
      assert Protocol.decode_command(:configuration, <<0x07, 0x05, "hello">>) == :error
      assert Protocol.decode_command(:login, <<0x07, 0x05, "hello">>) == :error
    end

    test "returns :error for other packets" do
      # chat_message (0x09) with the text "hello"
      assert Protocol.decode_command(:play, <<0x09, 0x05, "hello">>) == :error
      # chat_command_signed (0x08)
      assert Protocol.decode_command(:play, <<0x08, 0x05, "hello">>) == :error
    end

    test "returns :error when the command is cut" do
      assert Protocol.decode_command(:play, <<0x07, 0x05, "hel">>) == :error
    end
  end

  # Feeds the chunks one by one, like successive TCP reads, keeping the
  # leftover bytes between calls. Returns every frame it got, in order.
  defp feed(chunks) do
    {frames, rest} =
      Enum.reduce(chunks, {[], <<>>}, fn chunk, {frames, buffer} ->
        {:ok, new_frames, rest} = Protocol.split_frames(buffer <> chunk)
        {frames ++ new_frames, rest}
      end)

    assert rest == <<>>
    frames
  end

  describe "decode_position/2" do
    # position (0x1E): x, y and z as 64-bit floats, then the movement flags
    test "returns the coordinates of a position packet in play" do
      frame = <<0x1E, 1.5::float-64, 64.0::float-64, -2.25::float-64, 0x01>>

      assert Protocol.decode_position(:play, frame) == {:ok, {1.5, 64.0, -2.25}}
    end

    # position_look (0x1F): the same coordinates, then yaw, pitch and flags
    test "returns the coordinates of a position_look packet in play" do
      frame =
        <<0x1F, 1.5::float-64, 64.0::float-64, -2.25::float-64, 90.0::float-32, 0.0::float-32,
          0x00>>

      assert Protocol.decode_position(:play, frame) == {:ok, {1.5, 64.0, -2.25}}
    end

    test "returns :error for packets without a position" do
      # look (0x20): only yaw, pitch and flags
      assert Protocol.decode_position(:play, <<0x20, 90.0::float-32, 0.0::float-32, 0x00>>) ==
               :error

      # chat_command (0x07)
      assert Protocol.decode_position(:play, <<0x07, 0x05, "hello">>) == :error
    end

    test "returns :error outside play" do
      frame = <<0x1E, 1.5::float-64, 64.0::float-64, -2.25::float-64, 0x01>>

      assert Protocol.decode_position(:configuration, frame) == :error
    end

    test "returns :error when the coordinates are cut" do
      assert Protocol.decode_position(:play, <<0x1E, 1.5::float-64, 64.0::float-64>>) == :error
    end
  end

  describe "decode_entity_event/2" do
    # Entity 42 (0x2A as a VarInt) in every frame
    @uuid :binary.copy(<<0xAB>>, 16)

    test "returns the id, type and position of a spawned entity" do
      # spawn_entity (0x01): id, UUID, type (150 = zombie), x, y, z,
      # then velocity, angles and data, which are not read
      frame =
        <<0x01, 0x2A>> <>
          @uuid <>
          <<0x96, 0x01, 1.5::float-64, 64.0::float-64, -2.25::float-64>> <>
          <<0x00, 0x00, 0x00, 0x00, 0x00>>

      assert Protocol.decode_entity_event(:play, frame) == {:spawn, 42, 150, {1.5, 64.0, -2.25}}
    end

    test "returns a relative move in blocks" do
      # rel_entity_move (0x35): id, dx, dy, dz in 1/4096 of a block, on ground
      frame = <<0x35, 0x2A, 4096::signed-16, -8192::signed-16, 2048::signed-16, 0x01>>

      assert Protocol.decode_entity_event(:play, frame) == {:move, 42, {1.0, -2.0, 0.5}}
    end

    test "returns a relative move that also turns the entity" do
      # entity_move_look (0x36): the same deltas, then yaw, pitch and on ground
      frame = <<0x36, 0x2A, 4096::signed-16, 0::signed-16, -4096::signed-16, 0x10, 0x20, 0x01>>

      assert Protocol.decode_entity_event(:play, frame) == {:move, 42, {1.0, 0.0, -1.0}}
    end

    test "returns the new position of sync_entity_position" do
      # sync_entity_position (0x23): id, x, y, z, velocity, yaw, pitch, on ground
      frame =
        <<0x23, 0x2A, 1.5::float-64, 64.0::float-64, -2.25::float-64>> <>
          <<0.0::float-64, 0.0::float-64, 0.0::float-64, 0.0::float-32, 0.0::float-32, 0x01>>

      assert Protocol.decode_entity_event(:play, frame) == {:teleport, 42, {1.5, 64.0, -2.25}}
    end

    test "returns the new position of entity_teleport" do
      # entity_teleport (0x7D): id, x, y, z, velocity, yaw, pitch, flags, on ground
      frame =
        <<0x7D, 0x2A, 1.5::float-64, 64.0::float-64, -2.25::float-64>> <>
          <<0.0::float-64, 0.0::float-64, 0.0::float-64, 0.0::float-32, 0.0::float-32>> <>
          <<0::32, 0x01>>

      assert Protocol.decode_entity_event(:play, frame) == {:teleport, 42, {1.5, 64.0, -2.25}}
    end

    test "returns the ids of removed entities" do
      # entity_destroy (0x4D): how many ids, then the ids (42 and 150)
      assert Protocol.decode_entity_event(:play, <<0x4D, 0x02, 0x2A, 0x96, 0x01>>) ==
               {:remove, [42, 150]}
    end

    test "returns :error for other packets" do
      assert Protocol.decode_entity_event(:play, <<0x79, 0x00>>) == :error
    end

    test "returns :error outside play" do
      frame = <<0x35, 0x2A, 4096::signed-16, -8192::signed-16, 2048::signed-16, 0x01>>

      assert Protocol.decode_entity_event(:configuration, frame) == :error
    end

    test "returns :error when the frame is cut" do
      assert Protocol.decode_entity_event(:play, <<0x35, 0x2A, 0x10>>) == :error
      assert Protocol.decode_entity_event(:play, <<0x4D, 0x02, 0x2A>>) == :error
    end
  end

  describe "decode_yaw/2" do
    # position_look (0x1F): x, y, z, then yaw and pitch as 32-bit floats, then flags
    test "returns the yaw of a position_look packet in play" do
      frame =
        <<0x1F, 1.5::float-64, 64.0::float-64, -2.25::float-64, 90.0::float-32, 30.0::float-32,
          0x00>>

      assert Protocol.decode_yaw(:play, frame) == {:ok, 90.0}
    end

    # look (0x20): only yaw, pitch and flags
    test "returns the yaw of a look packet in play" do
      frame = <<0x20, -45.0::float-32, 30.0::float-32, 0x00>>

      assert Protocol.decode_yaw(:play, frame) == {:ok, -45.0}
    end

    test "returns :error for packets without a rotation" do
      # position (0x1E): x, y, z and flags
      frame = <<0x1E, 1.5::float-64, 64.0::float-64, -2.25::float-64, 0x01>>

      assert Protocol.decode_yaw(:play, frame) == :error
    end

    test "returns :error outside play" do
      assert Protocol.decode_yaw(:configuration, <<0x20, -45.0::float-32, 30.0::float-32, 0x00>>) ==
               :error
    end

    test "returns :error when the yaw is cut" do
      assert Protocol.decode_yaw(:play, <<0x20, 0x00, 0x00>>) == :error
    end
  end
end
