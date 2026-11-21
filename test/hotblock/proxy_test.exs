defmodule Hotblock.ProxyTest do
  # async: false because the proxy listens on a fixed port
  use ExUnit.Case, async: false

  alias Hotblock.Protocol.Encoder.{Clientbound, Serverbound}

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

      expected = Clientbound.system_chat(Hotblock.Commands.help_text())
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

  describe "/hotblock:fx weather" do
    # chat_command (0x07) with the command "hotblock:fx weather rain"
    @fx_rain <<0x1A, 0x07, 0x18, "hotblock:fx weather rain">>

    # game_state_change (0x26) start_raining, rain level 1, thunder level 0
    @rain_reply <<0x06, 0x26, 0x01, 0.0::float-32>> <>
                  <<0x06, 0x26, 0x07, 1.0::float-32>> <>
                  <<0x06, 0x26, 0x08, 0.0::float-32>>

    test "does not forward /hotblock:fx weather to the server in play", %{listen: listen} do
      {client, server} = connect(listen)

      :ok = :gen_tcp.send(client, @to_play <> @fx_rain <> @other)

      expected = @to_play <> @other
      assert {:ok, ^expected} = :gen_tcp.recv(server, byte_size(expected), 1000)
      assert {:error, :timeout} = :gen_tcp.recv(server, 0, 200)
    end

    test "sends the weather packets to the client", %{listen: listen} do
      {client, _server} = connect(listen)

      :ok = :gen_tcp.send(client, @to_play <> @fx_rain)
      assert {:ok, @rain_reply} = :gen_tcp.recv(client, byte_size(@rain_reply), 1000)
    end

    test "only changes the weather of the player who typed it", %{listen: listen} do
      {client1, _server1} = connect(listen)
      {client2, _server2} = connect(listen)

      :ok = :gen_tcp.send(client1, @to_play <> @fx_rain)

      assert {:ok, @rain_reply} = :gen_tcp.recv(client1, byte_size(@rain_reply), 1000)
      assert {:error, :timeout} = :gen_tcp.recv(client2, 0, 200)
    end

    test "forwards an unknown weather to the server", %{listen: listen} do
      {client, server} = connect(listen)

      fx_snow = <<0x1A, 0x07, 0x18, "hotblock:fx weather snow">>
      :ok = :gen_tcp.send(client, @to_play <> fx_snow)

      expected = @to_play <> fx_snow
      assert {:ok, ^expected} = :gen_tcp.recv(server, byte_size(expected), 1000)
      assert {:error, :timeout} = :gen_tcp.recv(client, 0, 200)
    end
  end

  describe "/hotblock:fx bar" do
    # chat_command (0x07) with the command "hotblock:fx bar 50 red Hi"
    @fx_bar <<0x1B, 0x07, 0x19, "hotblock:fx bar 50 red Hi">>

    # chat_command (0x07) with the command "hotblock:fx bar off"
    @fx_bar_off <<0x15, 0x07, 0x13, "hotblock:fx bar off">>

    test "does not forward /hotblock:fx bar to the server in play", %{listen: listen} do
      {client, server} = connect(listen)

      :ok = :gen_tcp.send(client, @to_play <> @fx_bar <> @fx_bar_off <> @other)

      expected = @to_play <> @other
      assert {:ok, ^expected} = :gen_tcp.recv(server, byte_size(expected), 1000)
      assert {:error, :timeout} = :gen_tcp.recv(server, 0, 200)
    end

    test "adds the bar the first time", %{listen: listen} do
      {client, _server} = connect(listen)

      :ok = :gen_tcp.send(client, @to_play <> @fx_bar)

      expected = Clientbound.boss_bar_add("Hi", 0.5, :red)
      assert {:ok, ^expected} = :gen_tcp.recv(client, byte_size(expected), 1000)
    end

    test "updates the same bar the second time, so there are no duplicates",
         %{listen: listen} do
      {client, _server} = connect(listen)

      # chat_command (0x07) with the command "hotblock:fx bar 80 red Hi"
      fx_bar_80 = <<0x1B, 0x07, 0x19, "hotblock:fx bar 80 red Hi">>
      :ok = :gen_tcp.send(client, @to_play <> @fx_bar <> fx_bar_80)

      expected =
        Clientbound.boss_bar_add("Hi", 0.5, :red) <> Clientbound.boss_bar_update_health(0.8)

      assert {:ok, ^expected} = :gen_tcp.recv(client, byte_size(expected), 1000)
      assert {:error, :timeout} = :gen_tcp.recv(client, 0, 200)
    end

    test "removes the bar with off", %{listen: listen} do
      {client, _server} = connect(listen)

      :ok = :gen_tcp.send(client, @to_play <> @fx_bar <> @fx_bar_off)

      expected = Clientbound.boss_bar_add("Hi", 0.5, :red) <> Clientbound.boss_bar_remove()
      assert {:ok, ^expected} = :gen_tcp.recv(client, byte_size(expected), 1000)
    end

    test "does nothing with off when there is no bar", %{listen: listen} do
      {client, server} = connect(listen)

      :ok = :gen_tcp.send(client, @to_play <> @fx_bar_off)

      assert {:ok, @to_play} = :gen_tcp.recv(server, byte_size(@to_play), 1000)
      assert {:error, :timeout} = :gen_tcp.recv(client, 0, 200)
      assert {:error, :timeout} = :gen_tcp.recv(server, 0, 200)
    end

    test "forwards an invalid /hotblock:fx bar to the server", %{listen: listen} do
      {client, server} = connect(listen)

      fx_bar_invalid = <<0x1C, 0x07, 0x1A, "hotblock:fx bar 500 red Hi">>
      :ok = :gen_tcp.send(client, @to_play <> fx_bar_invalid)

      expected = @to_play <> fx_bar_invalid
      assert {:ok, ^expected} = :gen_tcp.recv(server, byte_size(expected), 1000)
      assert {:error, :timeout} = :gen_tcp.recv(client, 0, 200)
    end
  end

  describe "/hotblock:fx sound" do
    # position (0x1E) at x 1.5, y 64, z -2.25, on the ground
    @position <<0x1A, 0x1E, 1.5::float-64, 64.0::float-64, -2.25::float-64, 0x01>>

    # chat_command (0x07) with the command "hotblock:fx sound entity.player.levelup"
    @fx_sound <<0x29, 0x07, 0x27, "hotblock:fx sound entity.player.levelup">>

    test "forwards the position but not the command to the server", %{listen: listen} do
      {client, server} = connect(listen)

      :ok = :gen_tcp.send(client, @to_play <> @position <> @fx_sound <> @other)

      expected = @to_play <> @position <> @other
      assert {:ok, ^expected} = :gen_tcp.recv(server, byte_size(expected), 1000)
      assert {:error, :timeout} = :gen_tcp.recv(server, 0, 200)
    end

    test "plays the sound at the last position the client sent", %{listen: listen} do
      {client, _server} = connect(listen)

      :ok = :gen_tcp.send(client, @to_play <> @position <> @fx_sound)

      expected = Clientbound.sound_effect("minecraft:entity.player.levelup", {1.5, 64.0, -2.25})
      assert {:ok, ^expected} = :gen_tcp.recv(client, byte_size(expected), 1000)
    end

    test "replies with a chat error for an unknown sound", %{listen: listen} do
      {client, server} = connect(listen)

      # chat_command (0x07) with the command "hotblock:fx sound entity.player.dance"
      fx_unknown = <<0x27, 0x07, 0x25, "hotblock:fx sound entity.player.dance">>
      :ok = :gen_tcp.send(client, @to_play <> @position <> fx_unknown)

      expected = Clientbound.system_chat("Unknown sound: entity.player.dance")
      assert {:ok, ^expected} = :gen_tcp.recv(client, byte_size(expected), 1000)

      forwarded = @to_play <> @position
      assert {:ok, ^forwarded} = :gen_tcp.recv(server, byte_size(forwarded), 1000)
      assert {:error, :timeout} = :gen_tcp.recv(server, 0, 200)
    end
  end

  describe "/hotblock:watch" do
    # position (0x1E): the player at x 0, y 64, z 0
    @at_origin <<0x1A, 0x1E, 0.0::float-64, 64.0::float-64, 0.0::float-64, 0x01>>

    # chat_command (0x07) with the command "hotblock:watch zombie 10"
    @watch_zombie <<0x1A, 0x07, 0x18, "hotblock:watch zombie 10">>

    # chat_command (0x07) with the command "hotblock:unwatch zombie"
    @unwatch_zombie <<0x19, 0x07, 0x17, "hotblock:unwatch zombie">>

    # spawn_entity (0x01): entity 42, a zombie (type 150), 3 blocks from the player
    @zombie_spawn <<0x31, 0x01, 0x2A>> <>
                    :binary.copy(<<0xAB>>, 16) <>
                    <<0x96, 0x01, 3.0::float-64, 64.0::float-64, 0.0::float-64>> <>
                    <<0x00, 0x00, 0x00, 0x00, 0x00>>

    @watching Clientbound.system_chat("Watching zombie within 10 blocks")

    test "confirms the watch and does not forward the command", %{listen: listen} do
      {client, server} = connect(listen)

      :ok = :gen_tcp.send(client, @to_play <> @at_origin <> @watch_zombie <> @other)

      assert {:ok, @watching} = :gen_tcp.recv(client, byte_size(@watching), 1000)

      expected = @to_play <> @at_origin <> @other
      assert {:ok, ^expected} = :gen_tcp.recv(server, byte_size(expected), 1000)
      assert {:error, :timeout} = :gen_tcp.recv(server, 0, 200)
    end

    test "warns when a watched entity spawns within the radius", %{listen: listen} do
      {client, server} = connect(listen)

      :ok = :gen_tcp.send(client, @to_play <> @at_origin <> @watch_zombie)
      assert {:ok, @watching} = :gen_tcp.recv(client, byte_size(@watching), 1000)

      :ok = :gen_tcp.send(server, @zombie_spawn)

      expected =
        @zombie_spawn <>
          Clientbound.action_bar("zombie 3 blocks away!") <>
          Clientbound.sound_effect("minecraft:block.note_block.pling", {0.0, 64.0, 0.0})

      assert {:ok, ^expected} = :gen_tcp.recv(client, byte_size(expected), 1000)
    end

    test "stops warning after /hotblock:unwatch", %{listen: listen} do
      {client, server} = connect(listen)

      :ok = :gen_tcp.send(client, @to_play <> @at_origin <> @watch_zombie <> @unwatch_zombie)

      replies = @watching <> Clientbound.system_chat("Stopped watching zombie")
      assert {:ok, ^replies} = :gen_tcp.recv(client, byte_size(replies), 1000)

      :ok = :gen_tcp.send(server, @zombie_spawn)
      assert {:ok, @zombie_spawn} = :gen_tcp.recv(client, byte_size(@zombie_spawn), 1000)
      assert {:error, :timeout} = :gen_tcp.recv(client, 0, 200)
    end

    test "replies with a chat error for an unknown entity", %{listen: listen} do
      {client, _server} = connect(listen)

      # chat_command (0x07) with the command "hotblock:watch dragon"
      :ok = :gen_tcp.send(client, @to_play <> <<0x17, 0x07, 0x15, "hotblock:watch dragon">>)

      expected = Clientbound.system_chat("Unknown entity: dragon")
      assert {:ok, ^expected} = :gen_tcp.recv(client, byte_size(expected), 1000)
    end
  end

  describe "/hotblock:spawn" do
    # position_look (0x1F): the player at x 0, y 64, z 0, facing south (yaw 0)
    @facing_south <<0x22, 0x1F, 0.0::float-64, 64.0::float-64, 0.0::float-64>> <>
                    <<0.0::float-32, 0.0::float-32, 0x01>>

    # chat_command (0x07) with the command "hotblock:spawn zombie"
    @spawn_zombie <<0x17, 0x07, 0x15, "hotblock:spawn zombie">>

    test "sends a summon command 3 blocks behind the player to the server",
         %{listen: listen} do
      {client, server} = connect(listen)

      :ok = :gen_tcp.send(client, @to_play <> @facing_south <> @spawn_zombie <> @other)

      expected =
        @to_play <>
          @facing_south <>
          Serverbound.chat_command("summon minecraft:zombie 0.00 64.00 -3.00") <>
          @other

      assert {:ok, ^expected} = :gen_tcp.recv(server, byte_size(expected), 1000)
      assert {:error, :timeout} = :gen_tcp.recv(server, 0, 200)
      assert {:error, :timeout} = :gen_tcp.recv(client, 0, 200)
    end

    test "uses the distance and direction from the command", %{listen: listen} do
      {client, server} = connect(listen)

      # chat_command (0x07) with the command "hotblock:spawn zombie 5 front"
      :ok =
        :gen_tcp.send(
          client,
          @to_play <> @facing_south <> <<0x1F, 0x07, 0x1D, "hotblock:spawn zombie 5 front">>
        )

      expected =
        @to_play <>
          @facing_south <>
          Serverbound.chat_command("summon minecraft:zombie 0.00 64.00 5.00")

      assert {:ok, ^expected} = :gen_tcp.recv(server, byte_size(expected), 1000)
      assert {:error, :timeout} = :gen_tcp.recv(client, 0, 200)
    end

    test "replies with a chat error for an unknown entity and sends nothing to the server",
         %{listen: listen} do
      {client, server} = connect(listen)

      # chat_command (0x07) with the command "hotblock:spawn dragon"
      :ok =
        :gen_tcp.send(
          client,
          @to_play <> @facing_south <> <<0x17, 0x07, 0x15, "hotblock:spawn dragon">>
        )

      expected = Clientbound.system_chat("Unknown entity: dragon")
      assert {:ok, ^expected} = :gen_tcp.recv(client, byte_size(expected), 1000)

      forwarded = @to_play <> @facing_south
      assert {:ok, ^forwarded} = :gen_tcp.recv(server, byte_size(forwarded), 1000)
      assert {:error, :timeout} = :gen_tcp.recv(server, 0, 200)
    end
  end
end
