defmodule Hotblock.Proxy do
  alias Hotblock.Commands
  alias Hotblock.Effects.BossBar
  alias Hotblock.Effects.EntityWatch
  alias Hotblock.Effects.Sound
  alias Hotblock.Effects.Spawn
  alias Hotblock.PacketLogger
  alias Hotblock.Protocol
  alias Hotblock.Protocol.Encoder
  alias Hotblock.Protocol.Encoder.Clientbound
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
      case Protocol.decode_command(phase, frame) do
        {:ok, "hotblock:hello"} ->
          :gen_tcp.send(state.client, Clientbound.system_chat("Hello from Elixir!"))
          state

        {:ok, "hotblock:fx title " <> text} when text != "" ->
          send_title(state.client, text)
          state

        {:ok, "hotblock:fx actionbar " <> text} when text != "" ->
          :gen_tcp.send(state.client, Clientbound.action_bar(text))
          state

        {:ok, "hotblock:fx weather " <> weather} when weather in ["clear", "rain", "thunder"] ->
          :gen_tcp.send(state.client, Clientbound.weather(String.to_existing_atom(weather)))
          state

        {:ok, "hotblock:fx bar off"} ->
          set_boss_bar(state, nil)

        {:ok, "hotblock:fx bar " <> args} ->
          case Commands.parse_bar(args) do
            {:ok, health, color, text} ->
              set_boss_bar(state, %{title: text, health: health, color: color})

            :error ->
              :gen_tcp.send(state.server, Encoder.encode_frame(frame))
              state
          end

        {:ok, "hotblock:watch " <> args} ->
          case Commands.parse_watch(args) do
            {:ok, name, radius} ->
              {reply, entity_watch} = EntityWatch.watch(state.entity_watch, name, radius)
              :gen_tcp.send(state.client, reply)
              %{state | entity_watch: entity_watch}

            :error ->
              :gen_tcp.send(state.server, Encoder.encode_frame(frame))
              state
          end

        {:ok, "hotblock:unwatch " <> name} when name != "" ->
          {reply, entity_watch} = EntityWatch.unwatch(state.entity_watch, name)
          :gen_tcp.send(state.client, reply)
          %{state | entity_watch: entity_watch}

        {:ok, "hotblock:help"} ->
          :gen_tcp.send(state.client, Clientbound.system_chat(Commands.help_text()))
          state

        {:ok, "hotblock:fx sound " <> name} ->
          :gen_tcp.send(state.client, Sound.packets(name, state.position))
          state

        {:ok, "hotblock:spawn " <> args} ->
          case Commands.parse_spawn(args) do
            {:ok, name, distance, direction} ->
              case Spawn.packets(name, distance, direction, state.position, state.yaw) do
                {:client, packet} ->
                  :gen_tcp.send(state.client, packet)
                  state

                {:server, packet} ->
                  :gen_tcp.send(state.server, packet)
                  state
              end

            :error ->
              :gen_tcp.send(state.server, Encoder.encode_frame(frame))
              state
          end

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

  # The text is "<title>" or "<title> | <subtitle>"
  defp send_title(client, text) do
    {title, subtitle} =
      case String.split(text, " | ", parts: 2) do
        [title, subtitle] -> {title, subtitle}
        [title] -> {title, ""}
      end

    :gen_tcp.send(client, Clientbound.set_title_time(10, 70, 20))
    :gen_tcp.send(client, Clientbound.set_title_subtitle(subtitle))
    :gen_tcp.send(client, Clientbound.set_title_text(title))
  end

  # Sends what changed from the current bar to the new one and remembers it
  defp set_boss_bar(state, bar) do
    :gen_tcp.send(state.client, BossBar.packets(state.boss_bar, bar))
    %{state | boss_bar: bar}
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
