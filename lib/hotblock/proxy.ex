defmodule Hotblock.Proxy do
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
      DynamicSupervisor.start_child(Hotblock.ConnectionSupervisor, {Hotblock.Connection, client})

    :gen_tcp.controlling_process(client, pid)
    Hotblock.Connection.activate(pid)
    __MODULE__.loop_acceptor(socket)
  end
end
