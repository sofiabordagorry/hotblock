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

  def next_state(:handshaking, <<0x00, payload::binary>>) do
    case decode_handshake(payload) do
      {:ok, %{intent: 1}} -> {:ok, :status}
      {:ok, %{intent: intent}} when intent in [2, 3] -> {:ok, :login}
      {:ok, _handshake} -> {:error, :invalid_intent}
      {:error, reason} -> {:error, reason}
    end
  end

  def next_state(:login, <<0x03, _rest::binary>>), do: {:ok, :configuration}

  def next_state(:configuration, <<0x03, _rest::binary>>), do: {:ok, :play}

  def next_state(state, _frame), do: {:ok, state}

  def decode_handshake(payload) do
    with {:ok, protocol_version, rest} <- decode_varint(payload),
         {:ok, server_address, rest} <- decode_string(rest),
         <<server_port::16, rest::binary>> <- rest,
         {:ok, intent, <<>>} <- decode_varint(rest) do
      {:ok,
       %{
         protocol_version: protocol_version,
         server_address: server_address,
         server_port: server_port,
         intent: intent
       }}
    else
      _ -> {:error, :invalid_handshake}
    end
  end

  # A string is a VarInt with the length in bytes, followed by the UTF-8 bytes
  defp decode_string(binary) do
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

  def encode_frame(frame) do
    encode_varint(byte_size(frame)) <> frame
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
