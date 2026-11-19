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

  test "forwards frames from client to server", %{listen: listen} do
    {client, server} = connect(listen)

    :ok = :gen_tcp.send(client, <<0x03, 0xAA, 0xBB, 0xCC>>)
    assert {:ok, <<0x03, 0xAA, 0xBB, 0xCC>>} = :gen_tcp.recv(server, 0, 1000)
  end

  test "forwards a client frame that arrives in two parts", %{listen: listen} do
    {client, server} = connect(listen)

    :ok = :gen_tcp.send(client, <<0x03, 0xAA>>)
    :ok = :gen_tcp.send(client, <<0xBB, 0xCC>>)
    assert {:ok, <<0x03, 0xAA, 0xBB, 0xCC>>} = :gen_tcp.recv(server, 4, 1000)
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

    :ok = :gen_tcp.send(client1, <<0x01, 0x01>>)
    :ok = :gen_tcp.send(client2, <<0x01, 0x02>>)

    assert {:ok, <<0x01, 0x01>>} = :gen_tcp.recv(server1, 0, 1000)
    assert {:ok, <<0x01, 0x02>>} = :gen_tcp.recv(server2, 0, 1000)
  end

  describe "/hello" do
    # Frames that take the connection from handshaking to play:
    # handshake (intent 2), Login Acknowledged, Acknowledge Finish Configuration
    @to_play <<0x10, 0x00, 0x87, 0x06, 0x09, "localhost", 0x63, 0xDD, 0x02>> <>
               <<0x01, 0x03>> <>
               <<0x01, 0x03>>

    # chat_command (0x07) with the command "hello"
    @hello <<0x07, 0x07, 0x05, "hello">>

    # Any other play packet, sent last to check the connection still works
    @other <<0x02, 0x0B, 0xAA>>

    test "does not forward /hello to the server in play", %{listen: listen} do
      {client, server} = connect(listen)

      :ok = :gen_tcp.send(client, @to_play <> @hello <> @other)

      expected = @to_play <> @other
      assert {:ok, ^expected} = :gen_tcp.recv(server, byte_size(expected), 1000)
      assert {:error, :timeout} = :gen_tcp.recv(server, 0, 200)
    end

    test "forwards /hello when the connection is not in play yet", %{listen: listen} do
      {client, server} = connect(listen)

      :ok = :gen_tcp.send(client, @hello)
      assert {:ok, @hello} = :gen_tcp.recv(server, 0, 1000)
    end
  end
end
