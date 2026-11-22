defmodule Hotblock.PlayerTest do
  # async: false because the proxy listens on a fixed port
  use ExUnit.Case, async: false

  import Hotblock.ProxyHelpers

  alias Hotblock.Protocol.Encoder.Serverbound
  alias Hotblock.Rules

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

  test "the name is free again once the player disconnects", %{listen: listen} do
    {client, _server, pid} = join(listen, "Jeb")
    ref = Process.monitor(pid)

    :ok = :gen_tcp.close(client)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1000

    assert free?("Jeb")
  end
end
