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

  # A process that registers itself under a name, like a connection does
  defp fake_connection(name) do
    test = self()

    pid =
      spawn(fn ->
        {:ok, _} = Registry.register(Hotblock.PlayerRegistry, name, nil)
        send(test, :registered)
        Process.sleep(:infinity)
      end)

    assert_receive :registered
    on_exit(fn -> Process.exit(pid, :kill) end)
    pid
  end

  test "does not say a player left when the name is already back on a new connection" do
    # The old connection, as Players saw it when it registered
    old = spawn(fn -> Process.sleep(:infinity) end)
    on_exit(fn -> Process.exit(old, :kill) end)
    send(Players, {:register, Hotblock.PlayerRegistry, "Racer", old, nil})

    # The player reconnects, and the new connection registers before Players
    # hears that the old one ended
    _new = fake_connection("Racer")
    Phoenix.PubSub.subscribe(Hotblock.PubSub, "players")

    Process.exit(old, :kill)

    refute_receive {:player_left, "Racer"}, 200
  end

  test "after a restart, still says when players that were online leave" do
    ghost = fake_connection("Ghost")

    old_players = Process.whereis(Players)
    ref = Process.monitor(old_players)
    Process.exit(old_players, :kill)
    assert_receive {:DOWN, ^ref, :process, _, :killed}
    # The app's supervisor restarts Players when it gets the exit, so once it
    # answers this call, the new Players is running
    :sys.get_state(Hotblock.Supervisor)
    Phoenix.PubSub.subscribe(Hotblock.PubSub, "players")

    Process.exit(ghost, :kill)

    assert_receive {:player_left, "Ghost"}, 1000
  end
end
