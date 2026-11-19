defmodule Hotblock.Protocol do
  import Bitwise
  @max_frame_length 2_097_151

  def split_frames(buffer) do
    split_frames(buffer, [])
  end

  defp split_frames(buffer, acc) do
    case next_frame(buffer) do
      {:ok, frame, rest} ->
        split_frames(rest, [frame | acc])

      :incomplete ->
        {:ok, Enum.reverse(acc), buffer}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def next_frame(buffer) do
    case decode_varint(buffer) do
      {:ok, length, rest} ->
        cond do
          length < 0 or length > @max_frame_length ->
            {:error, :invalid_frame_length}

          byte_size(rest) < length ->
            :incomplete

          true ->
            <<frame::binary-size(^length), remaining::binary>> = rest
            {:ok, frame, remaining}
        end

      :incomplete ->
        :incomplete

      {:error, reason} ->
        {:error, reason}
    end
  end

  def decode_varint(binary) do
    decode_varint(binary, 0, 0)
  end

  # Already read 5 bytes, but still not done
  defp decode_varint(_binary, _acc, 35) do
    {:error, :varint_too_long}
  end

  # Read a byte with the continuation bit set, so we need to read more
  defp decode_varint(<<1::1, bits::7, rest::binary>>, acc, shift) do
    decode_varint(rest, acc ||| bits <<< shift, shift + 7)
  end

  # Read a byte with the continuation bit not set, so we are done
  defp decode_varint(<<0::1, bits::7, rest::binary>>, acc, shift) do
    {:ok, to_signed_32(acc ||| bits <<< shift), rest}
  end

  # No more bytes to read
  defp decode_varint(<<>>, _acc, _shift) do
    :incomplete
  end

  # A 5-byte varint carries 35 bits; keep only the low 32 like Minecraft does
  defp to_signed_32(value) when value > 0xFFFFFFFF do
    to_signed_32(value &&& 0xFFFFFFFF)
  end

  defp to_signed_32(value) when value >= 0x80000000 do
    value - 0x100000000
  end

  defp to_signed_32(value) do
    value
  end
end
