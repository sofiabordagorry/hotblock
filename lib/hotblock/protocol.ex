defmodule Hotblock.Protocol do
  alias Hotblock.Packets
  alias Hotblock.Protocol.Types

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
    case Types.decode_varint(buffer) do
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
    with {:ok, protocol_version, rest} <- Types.decode_varint(payload),
         {:ok, server_address, rest} <- Types.decode_string(rest),
         <<server_port::16, rest::binary>> <- rest,
         {:ok, intent, <<>>} <- Types.decode_varint(rest) do
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

  # True when the frame is a chat_command for /hello (it comes without the slash)

  def decode_command(:play, frame) do
    chat_command = Packets.chat_command()

    with {:ok, ^chat_command, rest} <- Types.decode_varint(frame),
         {:ok, command, <<>>} <- Types.decode_string(rest) do
      {:ok, command}
    else
      _ -> :error
    end
  end

  def decode_command(_phase, _frame), do: :error
end
