defmodule Hotblock.Protocol.Types do
  # Encoding and decoding of the basic data types of the protocol
  import Bitwise

  # A string is a VarInt with the length in bytes, followed by the UTF-8 bytes
  def decode_string(binary) do
    with {:ok, length, rest} when length >= 0 <- decode_varint(binary),
         <<string::binary-size(^length), remaining::binary>> <- rest do
      {:ok, string, remaining}
    else
      _ -> {:error, :invalid_string}
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

  def encode_varint(value) when value < 0 do
    encode_varint(value &&& 0xFFFFFFFF)
  end

  def encode_varint(value) when value < 0x80 do
    <<value>>
  end

  def encode_varint(value) do
    <<(value &&& 0x7F) ||| 0x80>> <> encode_varint(value >>> 7)
  end
end
