defmodule Hotblock.PlayersTest do
  # async: false because the proxy listens on a fixed port
  use ExUnit.Case, async: false

  import Hotblock.ProxyHelpers

  alias Hotblock.Players

  setup :listen_server

  test "list/0 has the players that joined, sorted", %{listen: listen} do
    join(listen, "Zed")
    join(listen, "Amy")

    # A player from another test may still be closing, so only these two count
    assert Enum.filter(Players.list(), &(&1 in ["Amy", "Zed"])) == ["Amy", "Zed"]
  end

  test "broadcasts when a player joins", %{listen: listen} do
    Phoenix.PubSub.subscribe(Hotblock.PubSub, "players")

    join(listen, "Alex")

    assert_receive {:player_joined, "Alex"}
  end

  test "broadcasts when a player disconnects", %{listen: listen} do
    {client, _server, _pid} = join(listen, "Alex")
    Phoenix.PubSub.subscribe(Hotblock.PubSub, "players")

    :ok = :gen_tcp.close(client)

    assert_receive {:player_left, "Alex"}, 1000
  end

  test "broadcasts when a connection is killed", %{listen: listen} do
    {_client, _server, pid} = join(listen, "Alex")
    Phoenix.PubSub.subscribe(Hotblock.PubSub, "players")

    Process.exit(pid, :kill)

    assert_receive {:player_left, "Alex"}, 1000
  end
end
