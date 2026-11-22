defmodule Hotblock.PlayerTest do
  # async: false because the proxy listens on a fixed port
  use ExUnit.Case, async: false

  import Hotblock.ProxyHelpers

  alias Hotblock.Connection
  alias Hotblock.Protocol.{Encoder, Types}
  alias Hotblock.Protocol.Encoder.{Clientbound, Serverbound}
  alias Hotblock.Rules

  # The type id of the zombie in minecraft-data 26.1
  @zombie 150

  setup :listen_server

  test "registers the connection under the player name", %{listen: listen} do
    {_client, _server, pid} = join(listen, "Alex")

    assert [{^pid, _}] = lookup("Alex")
    assert pid in connections()
  end

  test "a broadcast to player:<name> shows a title in that player's game", %{listen: listen} do
    {client, _server, _pid} = join(listen, "Steve")

    Phoenix.PubSub.broadcast(Hotblock.PubSub, "player:Steve", {:effect, :title, "hi"})

    {:ok, [{:client, title}], _state} = Rules.handle_effect(:title, "hi", %{})
    assert {:ok, ^title} = :gen_tcp.recv(client, byte_size(title), 1000)
  end

  test "a broadcast to another player does not reach this one", %{listen: listen} do
    {client, _server, _pid} = join(listen, "Notch")

    Phoenix.PubSub.broadcast(Hotblock.PubSub, "player:Herobrine", {:effect, :title, "hi"})

    assert {:error, :timeout} = :gen_tcp.recv(client, 0, 200)
  end

  test "a broadcast spawn reaches the server as a summon command", %{listen: listen} do
    {client, server, _pid} = join(listen, "Dinnerbone")
    to_play(client, server)
    move(client, server, {0.0, 64.0, 0.0})

    Phoenix.PubSub.broadcast(
      Hotblock.PubSub,
      "player:Dinnerbone",
      {:effect, :spawn, {"zombie", {1.0, 0.0}}}
    )

    summon = Serverbound.chat_command("summon minecraft:zombie 1.00 64.00 0.00")
    assert {:ok, ^summon} = :gen_tcp.recv(server, byte_size(summon), 1000)
  end

  describe "snapshot/1" do
    test "has the position, the yaw, the entities and the watches", %{listen: listen} do
      {client, server, pid} = join(listen, "Grumm")
      to_play(client, server)

      # position_look (0x1F): x, y, z, yaw, pitch, flags
      look =
        Encoder.encode_frame(
          <<0x1F, 1.0::float-64, 64.0::float-64, 2.0::float-64, 90.0::float-32, 0.0::float-32, 0>>
        )

      :ok = :gen_tcp.send(client, look)
      {:ok, ^look} = :gen_tcp.recv(server, byte_size(look), 1000)

      # spawn_entity (0x01): id, UUID, type, x, y, z, then fields the proxy ignores
      spawn =
        Encoder.encode_frame(
          <<0x01, 7, 0::128>> <>
            Types.encode_varint(@zombie) <>
            <<5.0::float-64, 64.0::float-64, 6.0::float-64, 0::64>>
        )

      :ok = :gen_tcp.send(server, spawn)
      {:ok, ^spawn} = :gen_tcp.recv(client, byte_size(spawn), 1000)

      Phoenix.PubSub.broadcast(Hotblock.PubSub, "player:Grumm", {:effect, :watch, {"zombie", 10}})

      assert %{
               position: {1.0, 64.0, 2.0},
               yaw: 90.0,
               entities: [%{type: "zombie", position: {5.0, 64.0, 6.0}}],
               watches: %{"zombie" => 10},
               boss_bar: nil
             } = Connection.snapshot(pid)
    end

    test "is :unavailable while the connection is suspended", %{listen: listen} do
      {_client, _server, pid} = join(listen, "Grumm")

      :ok = :sys.suspend(pid)
      assert Connection.snapshot(pid) == :unavailable
      :ok = :sys.resume(pid)

      assert %{position: nil} = Connection.snapshot(pid)
    end

    test "is :unavailable for a connection that is gone", %{listen: listen} do
      {_client, _server, pid} = join(listen, "Grumm")
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      assert Connection.snapshot(pid) == :unavailable
    end
  end

  describe "kick/2" do
    test "in play, sends the reason and closes both sockets", %{listen: listen} do
      {client, server, pid} = join(listen, "Grumm")
      to_play(client, server)

      Connection.kick(pid, "Bye")

      disconnect = Clientbound.disconnect("Bye")
      assert {:ok, ^disconnect} = :gen_tcp.recv(client, byte_size(disconnect), 1000)
      assert {:error, :closed} = :gen_tcp.recv(client, 0, 1000)
      assert {:error, :closed} = :gen_tcp.recv(server, 0, 1000)
    end

    test "before play, only closes the sockets", %{listen: listen} do
      {client, server, pid} = join(listen, "Grumm")

      Connection.kick(pid, "Bye")

      assert {:error, :closed} = :gen_tcp.recv(client, 0, 1000)
      assert {:error, :closed} = :gen_tcp.recv(server, 0, 1000)
    end
  end

  test "the name is free again once the player disconnects", %{listen: listen} do
    {client, _server, pid} = join(listen, "Jeb")
    ref = Process.monitor(pid)

    :ok = :gen_tcp.close(client)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1000

    assert free?("Jeb")
  end
end
