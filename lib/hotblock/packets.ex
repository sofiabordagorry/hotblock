defmodule Hotblock.Packets do
  # Packet IDs from minecraft-data, protocol 775 (26.1.2)

  # The client sends it when the player types a command.
  def chat_command, do: 0x07

  # Set the subtitle shown under the next title
  def set_title_subtitle, do: 0x70

  # Show a title in the center of the screen
  def set_title_text, do: 0x72

  # Set the fade-in, stay, and fade-out times for the title
  def set_title_time, do: 0x73

  # The server sends it to the client to display a system message in the chat.
  def system_chat, do: 0x79
end
