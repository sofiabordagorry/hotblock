defmodule Hotblock.Packets.Serverbound do
  # IDs of the play packets the client sends to the server.
  # From minecraft-data, protocol 775 (26.1.2).

  # A command the player typed, without the slash
  def chat_command, do: 0x07

  # The player's position
  def position, do: 0x1E

  # The player's position and rotation
  def position_look, do: 0x1F
end
