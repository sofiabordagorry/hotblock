defmodule Hotblock.Protocol.PropertiesTest do
  # Each property runs with thousands of random inputs, instead of a few
  # chosen by hand
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Hotblock.Protocol
  alias Hotblock.Protocol.{Encoder, Types}

  @runs 2_000

  # Signed 32-bit integers, the range of a VarInt
  defp varint, do: integer(-0x80000000..0x7FFFFFFF)

  # Frames, some long enough to need a length of 2 or 3 bytes
  defp frames do
    list_of(one_of([binary(max_length: 50), binary(min_length: 128, max_length: 20_000)]),
      max_length: 10
    )
  end

  # Cuts a binary into chunks of random sizes, like successive TCP reads
  defp chunks(binary) do
    gen all(cuts <- list_of(integer(0..byte_size(binary)), max_length: 20)) do
      points = Enum.sort(Enum.uniq([0, byte_size(binary) | cuts]))

      points
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [from, to] -> binary_part(binary, from, to - from) end)
    end
  end

  # Feeds the chunks one by one, keeping the leftover bytes between reads,
  # like the connection does
  defp feed(chunks) do
    Enum.reduce(chunks, {[], <<>>}, fn chunk, {frames, buffer} ->
      {:ok, new_frames, rest} = Protocol.split_frames(buffer <> chunk)
      {frames ++ new_frames, rest}
    end)
  end

  describe "VarInt" do
    property "decodes what was encoded, and keeps the bytes after it" do
      check all(value <- varint(), rest <- binary(), max_runs: @runs) do
        assert Types.decode_varint(Types.encode_varint(value) <> rest) == {:ok, value, rest}
      end
    end

    property "takes 1 to 5 bytes" do
      check all(value <- varint(), max_runs: @runs) do
        assert byte_size(Types.encode_varint(value)) in 1..5
      end
    end

    property "is :incomplete when cut before its last byte" do
      check all(value <- varint(), max_runs: @runs) do
        encoded = Types.encode_varint(value)

        for size <- 0..(byte_size(encoded) - 1) do
          assert Types.decode_varint(binary_part(encoded, 0, size)) == :incomplete
        end
      end
    end
  end

  describe "String" do
    property "decodes what was encoded, and keeps the bytes after it" do
      check all(string <- string(:printable), rest <- binary(), max_runs: @runs) do
        assert Types.decode_string(Types.encode_string(string) <> rest) == {:ok, string, rest}
      end
    end
  end

  describe "framing" do
    property "splits a stream back into the frames it was made of" do
      check all(frames <- frames(), max_runs: @runs) do
        stream = Enum.map_join(frames, &Encoder.encode_frame/1)

        assert Protocol.split_frames(stream) == {:ok, frames, <<>>}
      end
    end

    property "gives the same frames however the stream is cut into reads" do
      check all(
              frames <- frames(),
              chunks <- chunks(Enum.map_join(frames, &Encoder.encode_frame/1)),
              max_runs: @runs
            ) do
        assert feed(chunks) == {frames, <<>>}
      end
    end

    property "keeps an unfinished frame as the rest, without losing bytes" do
      check all(
              frames <- frames(),
              stream = Enum.map_join(frames, &Encoder.encode_frame/1),
              size <- integer(0..byte_size(stream)),
              max_runs: @runs
            ) do
        prefix = binary_part(stream, 0, size)
        {:ok, found, rest} = Protocol.split_frames(prefix)

        assert found == Enum.take(frames, length(found))
        assert Enum.map_join(found, &Encoder.encode_frame/1) <> rest == prefix
      end
    end

    property "never crashes on random bytes" do
      check all(bytes <- binary(), max_runs: @runs) do
        assert match?({:ok, _frames, _rest}, Protocol.split_frames(bytes)) or
                 match?({:error, _reason}, Protocol.split_frames(bytes))
      end
    end
  end
end
