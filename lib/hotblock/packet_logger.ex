defmodule Hotblock.PacketLogger do
  alias Hotblock.Protocol
  require Logger

  # Play packets the logger skips because they are sent all the time.
  # IDs from minecraft-data, protocol 775.
  @ignored_play_packets [
    # bundle_delimiter
    {:s2c, 0x00},
    # block_change
    {:s2c, 0x08},
    # chunk_batch_finished
    {:s2c, 0x0B},
    # chunk_batch_start
    {:s2c, 0x0C},
    # entity_status
    {:s2c, 0x22},
    # sync_entity_position
    {:s2c, 0x23},
    # unload_chunk
    {:s2c, 0x25},
    # keep_alive
    {:s2c, 0x2C},
    # map_chunk
    {:s2c, 0x2D},
    # update_light
    {:s2c, 0x30},
    # rel_entity_move
    {:s2c, 0x35},
    # entity_move_look
    {:s2c, 0x36},
    # entity_look
    {:s2c, 0x38},
    # entity_head_rotation
    {:s2c, 0x53},
    # multi_block_change
    {:s2c, 0x54},
    # update_view_position
    {:s2c, 0x5E},
    # entity_metadata
    {:s2c, 0x63},
    # entity_velocity
    {:s2c, 0x65},
    # update_time
    {:s2c, 0x71},
    # sound_effect
    {:s2c, 0x75},
    # entity_teleport
    {:s2c, 0x7D},
    # entity_update_attributes
    {:s2c, 0x83},
    # chunk_batch_received
    {:c2s, 0x0B},
    # tick_end
    {:c2s, 0x0D},
    # keep_alive
    {:c2s, 0x1C},
    # position
    {:c2s, 0x1E},
    # position_look
    {:c2s, 0x1F},
    # look
    {:c2s, 0x20},
    # flying
    {:c2s, 0x21},
    # player_input
    {:c2s, 0x2B}
  ]

  def log(phase, direction, frame) do
    if Application.get_env(:hotblock, :packet_logger_enabled, false) do
      {:ok, packet_id, _} = Protocol.decode_varint(frame)

      unless phase == :play and {direction, packet_id} in @ignored_play_packets do
        Logger.info(
          "{state: #{phase}, direction: #{direction}, " <>
            "packet_id: 0x#{Integer.to_string(packet_id, 16)}, size: #{byte_size(frame)}}"
        )
      end
    end
  end
end
