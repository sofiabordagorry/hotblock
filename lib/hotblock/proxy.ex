defmodule Hotblock.Proxy do
  alias Hotblock.{PacketLogger, Protocol}
  require Logger

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
        {:ok, frames, rest} = Protocol.split_frames(state.client_buffer <> data)
        phase = track_phase(state.phase, frames, server)

        loop(%{state | client_buffer: rest, phase: phase})

      {:tcp, ^server, data} ->
        {:ok, frames, rest} = Protocol.split_frames(state.server_buffer <> data)

        Enum.each(frames, fn frame ->
          PacketLogger.log(state.phase, :s2c, frame)
          :gen_tcp.send(client, Protocol.encode_frame(frame))
        end)

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
  defp track_phase(phase, frames, server) do
    Enum.reduce(frames, phase, fn frame, phase ->
      unless Protocol.hello_command?(phase, frame) do
        :gen_tcp.send(server, Protocol.encode_frame(frame))
      end

      PacketLogger.log(phase, :c2s, frame)
      {:ok, new_phase} = Protocol.next_state(phase, frame)

      if new_phase != phase do
        Logger.info("#{phase} -> #{new_phase}")
      end

      new_phase
    end)
  end
end
