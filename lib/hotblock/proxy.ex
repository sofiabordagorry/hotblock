defmodule Hotblock.Proxy do
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

  def accept(port) do
    {:ok, socket} = :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true])
    Logger.info("Listening on port #{port}")
    loop_acceptor(socket)
  end

  defp loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    Logger.info("Client connected")

    {:ok, pid} =
      Task.Supervisor.start_child(Hotblock.ConnectionSupervisor, fn -> serve(client) end)

    :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket)
  end

  defp serve(client) do
    server_port = Application.get_env(:hotblock, :server_port, 25566)

    {:ok, server} =
      :gen_tcp.connect(~c"localhost", server_port, [:binary, packet: :raw, active: true])

    Logger.info("Connected to server")
    :inet.setopts(client, active: true)

    loop(%{
      client: client,
      server: server,
      client_buffer: <<>>,
      server_buffer: <<>>,
      phase: :handshaking
    })
  end

  defp loop(%{client: client, server: server} = state) do
    receive do
      {:tcp, ^client, data} ->
        :gen_tcp.send(server, data)
        {:ok, frames, rest} = Protocol.split_frames(state.client_buffer <> data)
        phase = track_phase(state.phase, frames)

        loop(%{state | client_buffer: rest, phase: phase})

      {:tcp, ^server, data} ->
        :gen_tcp.send(client, data)
        {:ok, frames, rest} = Protocol.split_frames(state.server_buffer <> data)
        Enum.each(frames, fn frame -> log_packet(state.phase, :s2c, frame) end)
        loop(%{state | server_buffer: rest})

      {:tcp_closed, ^client} ->
        Logger.info("Client disconnected")
        :gen_tcp.close(server)

      {:tcp_closed, ^server} ->
        Logger.info("Server disconnected")
        :gen_tcp.close(client)
    end
  end

  # Runs the client's frames through the state machine in order, so a frame
  # is read with the phase set by the frames before it. Logs every change.
  defp track_phase(phase, frames) do
    Enum.reduce(frames, phase, fn frame, phase ->
      log_packet(phase, :c2s, frame)
      {:ok, new_phase} = Protocol.next_state(phase, frame)

      if new_phase != phase do
        Logger.info("#{phase} -> #{new_phase}")
      end

      new_phase
    end)
  end

  defp log_packet(phase, direction, frame) do
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
