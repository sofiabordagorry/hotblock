defmodule Hotblock.Packets.Clientbound do
  # IDs of the play packets the server sends to the client.
  # From minecraft-data, protocol 775 (26.1.2).

  # Create, update or remove a boss bar at the top of the screen
  def boss_bar, do: 0x09

  # Change a game state on the client, like the rain or the thunder
  def game_state_change, do: 0x26

  # Show a text above the hotbar
  def action_bar, do: 0x57

  # Set the subtitle shown under the next title
  def set_title_subtitle, do: 0x70

  # Show a title in the center of the screen
  def set_title_text, do: 0x72

  # Set the fade-in, stay, and fade-out times for the title
  def set_title_time, do: 0x73

  # Play a sound effect
  def sound_effect, do: 0x75

  # Show a system message in the chat
  def system_chat, do: 0x79
end
