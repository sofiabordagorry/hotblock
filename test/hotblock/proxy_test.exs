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

  test "forwards frames from server to client", %{listen: listen} do
    {client, server} = connect(listen)

    :ok = :gen_tcp.send(server, <<0x03, 0xAA, 0xBB, 0xCC>>)
    assert {:ok, <<0x03, 0xAA, 0xBB, 0xCC>>} = :gen_tcp.recv(client, 0, 1000)
  end

  test "forwards a server frame that arrives in two parts", %{listen: listen} do
    {client, server} = connect(listen)

    :ok = :gen_tcp.send(server, <<0x03, 0xAA>>)
    :ok = :gen_tcp.send(server, <<0xBB, 0xCC>>)
    assert {:ok, <<0x03, 0xAA, 0xBB, 0xCC>>} = :gen_tcp.recv(client, 4, 1000)
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

  describe "/hotblock:hello" do
    # Frames that take the connection from handshaking to play:
    # handshake (intent 2), Login Acknowledged, Acknowledge Finish Configuration
    @to_play <<0x10, 0x00, 0x87, 0x06, 0x09, "localhost", 0x63, 0xDD, 0x02>> <>
               <<0x01, 0x03>> <>
               <<0x01, 0x03>>

    # chat_command (0x07) with the command "hotblock:hello"
    @hello <<0x10, 0x07, 0x0E, "hotblock:hello">>

    # Any other play packet, sent last to check the connection still works
    @other <<0x02, 0x0B, 0xAA>>

    # system_chat (0x79) with {text: "Hello from Elixir!"} as NBT and overlay false
    @hello_reply <<0x1F, 0x79>> <>
                   <<0x0A, 0x08, 0x00, 0x04, "text", 0x00, 0x12, "Hello from Elixir!", 0x00>> <>
                   <<0x00>>

    test "does not forward /hotblock:hello to the server in play", %{listen: listen} do
      {client, server} = connect(listen)

      :ok = :gen_tcp.send(client, @to_play <> @hello <> @other)

      expected = @to_play <> @other
      assert {:ok, ^expected} = :gen_tcp.recv(server, byte_size(expected), 1000)
      assert {:error, :timeout} = :gen_tcp.recv(server, 0, 200)
    end

    test "replies to the client with a system_chat message", %{listen: listen} do
      {client, _server} = connect(listen)

      :ok = :gen_tcp.send(client, @to_play <> @hello)
      assert {:ok, @hello_reply} = :gen_tcp.recv(client, byte_size(@hello_reply), 1000)
    end

    test "does not put the reply in the middle of a server frame", %{listen: listen} do
      {client, server} = connect(listen)

      # The server frame arrives in two parts, with the /hotblock:hello in between
      :ok = :gen_tcp.send(server, <<0x03, 0xAA>>)
      :ok = :gen_tcp.send(client, @to_play <> @hello)
      assert {:ok, @hello_reply} = :gen_tcp.recv(client, byte_size(@hello_reply), 1000)

      :ok = :gen_tcp.send(server, <<0xBB, 0xCC>>)
      assert {:ok, <<0x03, 0xAA, 0xBB, 0xCC>>} = :gen_tcp.recv(client, 4, 1000)
    end

    test "forwards /hotblock:hello and does not reply when not in play yet", %{listen: listen} do
      {client, server} = connect(listen)

      :ok = :gen_tcp.send(client, @hello)
      assert {:ok, @hello} = :gen_tcp.recv(server, 0, 1000)
      assert {:error, :timeout} = :gen_tcp.recv(client, 0, 200)
    end
  end

  describe "/hotblock:fx title" do
    # chat_command (0x07) with the command "hotblock:fx title Hi"
    @fx_title <<0x16, 0x07, 0x14, "hotblock:fx title Hi">>

    # set_title_time (0x73) with fade in 10, stay 70 and fade out 20 ticks
    @title_time <<0x0D, 0x73, 10::32, 70::32, 20::32>>

    # set_title_subtitle (0x70) with {text: ""} as NBT
    @empty_subtitle <<0x0C, 0x70, 0x0A, 0x08, 0x00, 0x04, "text", 0x00, 0x00, 0x00>>

    # set_title_text (0x72) with {text: "Hi"} as NBT
    @title_text <<0x0E, 0x72, 0x0A, 0x08, 0x00, 0x04, "text", 0x00, 0x02, "Hi", 0x00>>

    @title_reply @title_time <> @empty_subtitle <> @title_text

    test "does not forward /hotblock:fx title to the server in play", %{listen: listen} do
      {client, server} = connect(listen)

      :ok = :gen_tcp.send(client, @to_play <> @fx_title <> @other)

      expected = @to_play <> @other
      assert {:ok, ^expected} = :gen_tcp.recv(server, byte_size(expected), 1000)
      assert {:error, :timeout} = :gen_tcp.recv(server, 0, 200)
    end

    test "sends the times, an empty subtitle and then the title text", %{listen: listen} do
      {client, _server} = connect(listen)

      :ok = :gen_tcp.send(client, @to_play <> @fx_title)
      assert {:ok, @title_reply} = :gen_tcp.recv(client, byte_size(@title_reply), 1000)
    end

    test "keeps the spaces in the text", %{listen: listen} do
      {client, _server} = connect(listen)

      :ok =
        :gen_tcp.send(client, @to_play <> <<0x1F, 0x07, 0x1D, "hotblock:fx title Hello world">>)

      expected =
        @title_time <>
          @empty_subtitle <>
          <<0x17, 0x72, 0x0A, 0x08, 0x00, 0x04, "text", 0x00, 0x0B, "Hello world", 0x00>>

      assert {:ok, ^expected} = :gen_tcp.recv(client, byte_size(expected), 1000)
    end

    test "sends the text after \" | \" as the subtitle", %{listen: listen} do
      {client, _server} = connect(listen)

      :ok =
        :gen_tcp.send(client, @to_play <> <<0x1E, 0x07, 0x1C, "hotblock:fx title Hi | there">>)

      expected =
        @title_time <>
          <<0x11, 0x70, 0x0A, 0x08, 0x00, 0x04, "text", 0x00, 0x05, "there", 0x00>> <>
          @title_text

      assert {:ok, ^expected} = :gen_tcp.recv(client, byte_size(expected), 1000)
    end

    test "forwards /hotblock:fx title without text to the server", %{listen: listen} do
      {client, server} = connect(listen)

      fx_title_empty = <<0x13, 0x07, 0x11, "hotblock:fx title">>
      :ok = :gen_tcp.send(client, @to_play <> fx_title_empty)

      expected = @to_play <> fx_title_empty
      assert {:ok, ^expected} = :gen_tcp.recv(server, byte_size(expected), 1000)
      assert {:error, :timeout} = :gen_tcp.recv(client, 0, 200)
    end
  end

  describe "/hotblock:help" do
    # chat_command (0x07) with the command "hotblock:help"
    @help <<0x0F, 0x07, 0x0D, "hotblock:help">>

    test "does not forward /hotblock:help to the server in play", %{listen: listen} do
      {client, server} = connect(listen)

      :ok = :gen_tcp.send(client, @to_play <> @help <> @other)

      expected = @to_play <> @other
      assert {:ok, ^expected} = :gen_tcp.recv(server, byte_size(expected), 1000)
      assert {:error, :timeout} = :gen_tcp.recv(server, 0, 200)
    end

    test "replies with the help text in the chat", %{listen: listen} do
      {client, _server} = connect(listen)

      :ok = :gen_tcp.send(client, @to_play <> @help)

      expected = Hotblock.Protocol.Encoder.system_chat(Hotblock.Commands.help_text())
      assert {:ok, ^expected} = :gen_tcp.recv(client, byte_size(expected), 1000)
    end
  end

  describe "/hotblock:fx actionbar" do
    # chat_command (0x07) with the command "hotblock:fx actionbar Hi"
    @fx_actionbar <<0x1A, 0x07, 0x18, "hotblock:fx actionbar Hi">>

    # action_bar (0x57) with {text: "Hi"} as NBT
    @actionbar_reply <<0x0E, 0x57, 0x0A, 0x08, 0x00, 0x04, "text", 0x00, 0x02, "Hi", 0x00>>

    test "does not forward /hotblock:fx actionbar to the server in play", %{listen: listen} do
      {client, server} = connect(listen)

      :ok = :gen_tcp.send(client, @to_play <> @fx_actionbar <> @other)

      expected = @to_play <> @other
      assert {:ok, ^expected} = :gen_tcp.recv(server, byte_size(expected), 1000)
      assert {:error, :timeout} = :gen_tcp.recv(server, 0, 200)
    end

    test "sends the text in an action_bar packet", %{listen: listen} do
      {client, _server} = connect(listen)

      :ok = :gen_tcp.send(client, @to_play <> @fx_actionbar)

      assert {:ok, @actionbar_reply} =
               :gen_tcp.recv(client, byte_size(@actionbar_reply), 1000)
    end

    test "forwards /hotblock:fx actionbar without text to the server", %{listen: listen} do
      {client, server} = connect(listen)

      fx_actionbar_empty = <<0x17, 0x07, 0x15, "hotblock:fx actionbar">>
      :ok = :gen_tcp.send(client, @to_play <> fx_actionbar_empty)

      expected = @to_play <> fx_actionbar_empty
      assert {:ok, ^expected} = :gen_tcp.recv(server, byte_size(expected), 1000)
      assert {:error, :timeout} = :gen_tcp.recv(client, 0, 200)
    end
  end
end
