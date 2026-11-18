defmodule Hotblock.Proxy do
  def accept(port) do
    {:ok, socket} = :gen_tcp.listen(port, [:binary, packet: :raw, active: false, reuseaddr: true])
    IO.puts("Listening on port #{port}")
    loop_acceptor(socket)
  end

  defp loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    IO.puts("Client connected")
    {:ok, pid} = Task.Supervisor.start_child(Hotblock.TaskSupervisor, fn -> serve(client) end)
    :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket)
  end

  defp serve(client) do
    {:ok, server} = :gen_tcp.connect(~c"localhost", 25566, [:binary, packet: :raw, active: true])
    IO.puts("Connected to server")
    :inet.setopts(client, active: true)
    loop(client, server)
  end

  defp loop(client, server) do
    receive do
      {:tcp, ^client, data} ->
        :gen_tcp.send(server, data)
        loop(client, server)

      {:tcp, ^server, data} ->
        :gen_tcp.send(client, data)
        loop(client, server)

      {:tcp_closed, ^client} ->
        IO.puts("Client disconnected")
        :gen_tcp.close(server)

      {:tcp_closed, ^server} ->
        IO.puts("Server disconnected")
        :gen_tcp.close(client)
    end
  end
end
