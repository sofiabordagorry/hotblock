defmodule Hotblock.ProxyTest do
  # async: false because the proxy listens on a fixed port
  use ExUnit.Case, async: false

  @proxy_port 25565
  @opts [:binary, packet: :raw, active: false]

  # Starts a fake upstream server on the port the proxy forwards to
  setup do
    server_port = Application.fetch_env!(:hotblock, :server_port)
    {:ok, listen} = :gen_tcp.listen(server_port, @opts ++ [reuseaddr: true])
    on_exit(fn -> :gen_tcp.close(listen) end)
    %{listen: listen}
  end

  # Connects a fake client to the proxy and accepts, on the fake server,
  # the connection the proxy opens. Order matters: client first.
  defp connect(listen) do
    {:ok, client} = :gen_tcp.connect(~c"localhost", @proxy_port, @opts)
    {:ok, server} = :gen_tcp.accept(listen, 1000)
    {client, server}
  end

  test "forwards data from client to server", %{listen: listen} do
    {client, server} = connect(listen)

    :ok = :gen_tcp.send(client, "hello server")
    assert {:ok, "hello server"} = :gen_tcp.recv(server, 0, 1000)
  end

  test "forwards data from server to client", %{listen: listen} do
    {client, server} = connect(listen)

    :ok = :gen_tcp.send(server, "hello client")
    assert {:ok, "hello client"} = :gen_tcp.recv(client, 0, 1000)
  end

  test "closes the server connection when the client disconnects", %{listen: listen} do
    {client, server} = connect(listen)

    :gen_tcp.close(client)
    assert {:error, :closed} = :gen_tcp.recv(server, 0, 1000)
  end

  test "closes the client connection when the server disconnects", %{listen: listen} do
    {client, server} = connect(listen)

    :gen_tcp.close(server)
    assert {:error, :closed} = :gen_tcp.recv(client, 0, 1000)
  end

  test "handles multiple players at once", %{listen: listen} do
    {client1, server1} = connect(listen)
    {client2, server2} = connect(listen)

    :ok = :gen_tcp.send(client1, "player 1")
    :ok = :gen_tcp.send(client2, "player 2")

    assert {:ok, "player 1"} = :gen_tcp.recv(server1, 0, 1000)
    assert {:ok, "player 2"} = :gen_tcp.recv(server2, 0, 1000)
  end
end
