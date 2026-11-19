defmodule Hotblock.Packets do
  # Packet IDs from minecraft-data, protocol 775 (26.1.2)

  # The client sends it when the player types a command.
  def chat_command, do: 0x07
end
