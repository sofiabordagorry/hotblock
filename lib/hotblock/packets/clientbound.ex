defmodule Hotblock.Packets.Clientbound do
  # IDs of the play packets the server sends to the client.
  # From minecraft-data, protocol 775 (26.1.2).

  # A new entity appears: its id, UUID, type and position
  def spawn_entity, do: 0x01

  # The tree of commands the client can autocomplete
  def declare_commands, do: 0x10

  # Create, update or remove a boss bar at the top of the screen
  def boss_bar, do: 0x09

  # The exact position of an entity, sent from time to time to fix small errors
  def sync_entity_position, do: 0x23

  # Change a game state on the client, like the rain or the thunder
  def game_state_change, do: 0x26

  # An entity moved a little, given as a change in position
  def rel_entity_move, do: 0x35

  # The same, but the entity also turned
  def entity_move_look, do: 0x36

  # Entities that are gone, by id
  def entity_destroy, do: 0x4D

  # Disconnect the player, with the reason shown on the screen
  # ("kick_disconnect" in minecraft-data)
  def disconnect, do: 0x20

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

  # An entity moved to a new position
  def entity_teleport, do: 0x7D
end
