defmodule Hotblock.Proxy do
  alias Hotblock.Protocol
  require Logger

  def accept(port) do
    {:ok, socket} = :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true])
    IO.puts("Listening on port #{port}")
    loop_acceptor(socket)
  end

  defp loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    IO.puts("Client connected")

    {:ok, pid} =
      Task.Supervisor.start_child(Hotblock.ConnectionSupervisor, fn -> serve(client) end)

    :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket)
  end

  defp serve(client) do
    server_port = Application.get_env(:hotblock, :server_port, 25566)

    {:ok, server} =
      :gen_tcp.connect(~c"localhost", server_port, [:binary, packet: :raw, active: true])

    IO.puts("Connected to server")
    :inet.setopts(client, active: true)
    loop(%{client: client, server: server, client_buffer: <<>>, server_buffer: <<>>})
  end

  defp loop(%{client: client, server: server} = state) do
    receive do
      {:tcp, ^client, data} ->
        :gen_tcp.send(server, data)
        {:ok, frames, rest} = Protocol.split_frames(state.client_buffer <> data)
        Logger.info("Received frames from client: #{inspect(frames)}")
        loop(%{state | client_buffer: rest})

      {:tcp, ^server, data} ->
        :gen_tcp.send(client, data)
        {:ok, frames, rest} = Protocol.split_frames(state.server_buffer <> data)
        Logger.info("Received frames from server: #{inspect(frames)}")
        loop(%{state | server_buffer: rest})

      {:tcp_closed, ^client} ->
        IO.puts("Client disconnected")
        :gen_tcp.close(server)

      {:tcp_closed, ^server} ->
        IO.puts("Server disconnected")
        :gen_tcp.close(client)
    end
  end
end
