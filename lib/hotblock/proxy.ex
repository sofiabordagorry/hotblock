defmodule Hotblock.Proxy do
  alias Hotblock.Effects.EntityWatch
  alias Hotblock.PacketLogger
  alias Hotblock.Protocol
  alias Hotblock.Protocol.Encoder
  alias Hotblock.Rules
  require Logger

  def accept(port) do
    {:ok, socket} = :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true])
    Logger.info("Listening on port #{port}")
    loop_acceptor(socket)
  end

  def loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    Logger.info("Client connected")

    {:ok, pid} =
      Task.Supervisor.start_child(Hotblock.ConnectionSupervisor, fn -> serve(client) end)

    :gen_tcp.controlling_process(client, pid)
    __MODULE__.loop_acceptor(socket)
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
      phase: :handshaking,
      boss_bar: nil,
      position: nil,
      entity_watch: EntityWatch.new(),
      yaw: nil
    })
  end

  def loop(%{client: client, server: server} = state) do
    receive do
      {:tcp, ^client, data} ->
        {:ok, frames, rest} = Protocol.split_frames(state.client_buffer <> data)
        state = Enum.reduce(frames, state, &handle_client_frame/2)
        __MODULE__.loop(%{state | client_buffer: rest})

      {:tcp, ^server, data} ->
        {:ok, frames, rest} = Protocol.split_frames(state.server_buffer <> data)
        state = Enum.reduce(frames, state, &handle_server_frame/2)
        __MODULE__.loop(%{state | server_buffer: rest})

      {:tcp_closed, ^client} ->
        Logger.info("Client disconnected")
        :gen_tcp.close(server)

      {:tcp_closed, ^server} ->
        Logger.info("Server disconnected")
        :gen_tcp.close(client)
    end
  end

  # Handles one frame from the server: logs it and forwards it to the client.
  # Entity packets also update the entity watch, which can send alerts.
  defp handle_server_frame(frame, state) do
    PacketLogger.log(state.phase, :s2c, frame)
    :gen_tcp.send(state.client, Encoder.encode_frame(frame))

    case Protocol.decode_entity_event(state.phase, frame) do
      :error ->
        state

      event ->
        state = %{state | entity_watch: EntityWatch.track(state.entity_watch, event)}
        send_alerts(state)
    end
  end

  defp handle_client_frame(frame, state) do
    phase = state.phase

    state =
      with {:ok, command} <- Protocol.decode_command(phase, frame),
           {:ok, sends, state} <- Rules.handle_command(command, state) do
        Enum.each(sends, fn
          {:client, packet} -> :gen_tcp.send(state.client, packet)
          {:server, packet} -> :gen_tcp.send(state.server, packet)
        end)

        state
      else
        _ ->
          :gen_tcp.send(state.server, Encoder.encode_frame(frame))
          state
      end

    state =
      case Protocol.decode_position(phase, frame) do
        {:ok, position} -> send_alerts(%{state | position: position})
        :error -> state
      end

    state =
      case Protocol.decode_yaw(phase, frame) do
        {:ok, yaw} -> %{state | yaw: yaw}
        :error -> state
      end

    PacketLogger.log(phase, :c2s, frame)
    {:ok, new_phase} = Protocol.next_state(phase, frame)

    if new_phase != phase do
      Logger.info("#{phase} -> #{new_phase}")
    end

    %{state | phase: new_phase}
  end

  # Sends the alerts for watched entities that are close and keeps the
  # cooldowns. Runs when an entity or the player moves.
  defp send_alerts(state) do
    now = System.monotonic_time(:millisecond)
    {packets, entity_watch} = EntityWatch.alerts(state.entity_watch, state.position, now)
    :gen_tcp.send(state.client, packets)
    %{state | entity_watch: entity_watch}
  end
end
