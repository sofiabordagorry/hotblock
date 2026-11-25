defmodule Hotblock.Connection do
  @moduledoc """
  This module represents the player's connection, it forwards packets 
  between client and server, and keeps the state of that player
  """
  use GenServer, restart: :temporary

  alias Hotblock.CommandTree
  alias Hotblock.Effects.EntityWatch
  alias Hotblock.PacketLogger
  alias Hotblock.Protocol
  alias Hotblock.Protocol.Encoder
  alias Hotblock.Protocol.Encoder.Clientbound
  alias Hotblock.Rules

  require Logger

  def start_link(client), do: GenServer.start_link(__MODULE__, client)

  # The proxy calls it once the client socket belongs to this process
  def activate(pid), do: send(pid, :activate)

  # where the player is and looks, the entities around and the watches
  def snapshot(pid) do
    GenServer.call(pid, :snapshot, 200)
  catch
    :exit, _reason -> :unavailable
  end

  # Disconnects the player, showing the reason
  def kick(pid, reason), do: send(pid, {:kick, reason})

  @impl true
  def init(client) do
    server_port = Application.get_env(:hotblock, :server_port, 25566)

    {:ok, server} =
      :gen_tcp.connect(~c"localhost", server_port, [:binary, packet: :raw, active: :once])

    Logger.info("Connected to server")

    {:ok,
     %{
       client: client,
       server: server,
       client_buffer: <<>>,
       server_buffer: <<>>,
       phase: :handshaking,
       boss_bar: nil,
       position: nil,
       entity_watch: EntityWatch.new(),
       yaw: nil,
       version: 2,
       stats: %{from_client: 0, from_server: 0}
     }}
  end

  # active: :once, so data the connection can't keep up with waits in the socket
  @impl true
  def handle_info(:activate, state) do
    :inet.setopts(state.client, active: :once)
    {:noreply, state}
  end

  def handle_info({:tcp, client, data}, %{client: client} = state) do
    {:ok, frames, rest} = Protocol.split_frames(state.client_buffer <> data)
    state = Enum.reduce(frames, state, &handle_client_frame/2)
    :inet.setopts(client, active: :once)
    {:noreply, %{state | client_buffer: rest}}
  end

  def handle_info({:tcp, server, data}, %{server: server} = state) do
    {:ok, frames, rest} = Protocol.split_frames(state.server_buffer <> data)
    state = Enum.reduce(frames, state, &handle_server_frame/2)
    :inet.setopts(server, active: :once)
    {:noreply, %{state | server_buffer: rest}}
  end

  def handle_info({:kick, reason}, state) do
    Logger.info("Kicked: #{reason}")

    # The disconnect packet has another ID outside play, so there the sockets
    # are just closed
    if state.phase == :play do
      :gen_tcp.send(state.client, Clientbound.disconnect(reason))
    end

    :gen_tcp.close(state.client)
    :gen_tcp.close(state.server)
    {:stop, :normal, state}
  end

  def handle_info({:tcp_closed, client}, %{client: client} = state) do
    Logger.info("Client disconnected")
    :gen_tcp.close(state.server)
    {:stop, :normal, state}
  end

  def handle_info({:tcp_closed, server}, %{server: server} = state) do
    Logger.info("Server disconnected")
    :gen_tcp.close(state.client)
    {:stop, :normal, state}
  end

  def handle_info({:effect, effect, arg}, state) do
    {:ok, sends, state} = Rules.handle_effect(effect, arg, state)
    send_all(sends, state)

    {:noreply, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    snapshot = %{
      position: state.position,
      yaw: state.yaw,
      entities: Map.values(state.entity_watch.entities),
      watches: state.entity_watch.watches,
      boss_bar: state.boss_bar
    }

    {:reply, snapshot, state}
  end

  # Handles one frame from the server: logs it and forwards it to the client.
  # Entity packets also update the entity watch, which can send alerts.
  defp handle_server_frame(frame, state) do
    state = update_in(state.stats.from_server, &(&1 + 1))
    Hotblock.Telemetry.packet(:from_server)
    PacketLogger.log(state.phase, :s2c, frame)

    :gen_tcp.send(
      state.client,
      Encoder.encode_frame(CommandTree.add_to_frame(state.phase, frame))
    )

    case Protocol.decode_entity_event(state.phase, frame) do
      :error ->
        state

      event ->
        state = %{state | entity_watch: EntityWatch.track(state.entity_watch, event)}
        send_alerts(state)
    end
  end

  defp handle_client_frame(frame, state) do
    state = update_in(state.stats.from_client, &(&1 + 1))
    Hotblock.Telemetry.packet(:from_client)

    phase = state.phase

    state =
      with {:ok, command} <- Protocol.decode_command(phase, frame),
           {:ok, sends, state} <- Rules.handle_command(command, state) do
        send_all(sends, state)
        state
      else
        _ ->
          :gen_tcp.send(state.server, Encoder.encode_frame(frame))
          state
      end

    case Protocol.decode_login_start(phase, frame) do
      {:ok, name} ->
        # If another connection already has this name, this one does not get
        # its effects either
        with {:ok, _} <- Registry.register(Hotblock.PlayerRegistry, name, nil) do
          Phoenix.PubSub.subscribe(Hotblock.PubSub, "player:" <> name)
        end

      :error ->
        :ok
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

  defp send_all(sends, state) do
    Enum.each(sends, fn
      {:client, packet} -> :gen_tcp.send(state.client, packet)
      {:server, packet} -> :gen_tcp.send(state.server, packet)
    end)
  end

  # Sends the alerts for watched entities that are close and keeps the
  # cooldowns. Runs when an entity or the player moves.
  defp send_alerts(state) do
    now = System.monotonic_time(:millisecond)
    {packets, entity_watch} = EntityWatch.alerts(state.entity_watch, state.position, now)
    :gen_tcp.send(state.client, packets)
    %{state | entity_watch: entity_watch}
  end

  # The state's shape changes between versions of this module. migrate/1 takes a
  # state from any older version to the current one. A state with no version is
  # from before version 2, which added the stats.
  def migrate(state) do
    case Map.get(state, :version, 1) do
      1 ->
        state
        |> Map.put(:version, 2)
        |> Map.put(:stats, %{from_client: 0, from_server: 0})

      _current ->
        state
    end
  end

  # Called by :sys.change_code/4 during a reload
  @impl true
  def code_change(_old_vsn, state, _extra), do: {:ok, migrate(state)}
end
