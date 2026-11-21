defmodule Hotblock.Protocol.Encoder.Serverbound do
  # The packets the proxy sends to the server, as if the client sent them
  alias Hotblock.Packets
  alias Hotblock.Protocol.{Encoder, Types}

  # A command sent to the server as if the player typed it, without the slash
  def chat_command(command) do
    Encoder.encode_packet(Packets.Serverbound.chat_command(), Types.encode_string(command))
  end
end
