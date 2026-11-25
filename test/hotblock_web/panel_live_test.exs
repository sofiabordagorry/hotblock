defmodule HotblockWeb.PanelLiveTest do
  # async: false because the list of players is global: other tests connect
  # real players through the proxy
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  import Hotblock.ProxyHelpers,
    only: [listen_server: 1, join: 2, to_play: 2, move: 3, free?: 1, wait_until_no_connections: 0]

  @endpoint HotblockWeb.Endpoint

  # Players from other tests may still be closing. The page lists the names in
  # the Registry, which frees them a moment after the connection ends.
  setup do
    wait_until_no_connections()
    for name <- Hotblock.Players.list(), do: assert(free?(name))
    %{conn: build_conn()}
  end

  # The page asks the connection for its state every 250 ms. Instead of
  # waiting for that, the test asks it to refresh now. render/1 answers once
  # the page has handled the refresh.
  defp refresh(view) do
    send(view.pid, :refresh)
    render(view)
  end

  # Players sends the page {:player_joined, name} when a connection registers.
  # Once Players answers this call, that message has been sent.
  defp players_told(view) do
    :sys.get_state(Hotblock.Players)
    render(view)
  end

  # Opens the panel with these players online. The players are not real
  # connections: the page only hears that they joined.
  defp panel(conn, players) do
    {:ok, view, _html} = live(conn, "/")
    for name <- players, do: send(view.pid, {:player_joined, name})
    render(view)
    view
  end

  defp listen_to(name), do: Phoenix.PubSub.subscribe(Hotblock.PubSub, "player:" <> name)

  describe "players" do
    test "shows that nobody is online", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      assert html =~ "Join the server through the proxy"
    end

    test "lists players live, and keeps the selection when someone else joins",
         %{conn: conn} do
      view = panel(conn, ["Steve", "Alex"])

      assert has_element?(view, "#players [data-player=Alex]")
      assert has_element?(view, "#players [data-player=Steve][aria-current=true]")
    end

    test "selects another player when clicked", %{conn: conn} do
      view = panel(conn, ["Steve", "Alex"])

      view |> element("#players [data-player=Alex]") |> render_click()

      assert has_element?(view, "#players [data-player=Alex][aria-current=true]")
    end

    test "selects the first remaining player when the selected one leaves", %{conn: conn} do
      view = panel(conn, ["Steve", "Alex"])

      send(view.pid, {:player_left, "Steve"})

      assert has_element?(view, "#players [data-player=Alex][aria-current=true]")
      refute has_element?(view, "#players [data-player=Steve]")
    end

    test "shows that nobody is online when the last player leaves", %{conn: conn} do
      view = panel(conn, ["Alex"])

      send(view.pid, {:player_left, "Alex"})

      assert render(view) =~ "Join the server through the proxy"
    end
  end

  describe "effects" do
    test "the title form broadcasts the effect", %{conn: conn} do
      view = panel(conn, ["Alex"])
      listen_to("Alex")

      html = view |> form("#title-form", %{text: "hi"}) |> render_submit()

      assert_receive {:effect, :title, "hi"}
      assert html =~ "Title sent to Alex"
    end

    test "the action bar form broadcasts the effect", %{conn: conn} do
      view = panel(conn, ["Alex"])
      listen_to("Alex")

      view |> form("#actionbar-form", %{text: "hey"}) |> render_submit()

      assert_receive {:effect, :actionbar, "hey"}
    end

    test "the weather buttons broadcast the effect", %{conn: conn} do
      view = panel(conn, ["Alex"])
      listen_to("Alex")

      for weather <- [:clear, :rain, :thunder] do
        view |> element("#weather-#{weather}") |> render_click()
        assert_receive {:effect, :weather, ^weather}
      end
    end

    test "the sound form broadcasts the effect", %{conn: conn} do
      view = panel(conn, ["Alex"])
      listen_to("Alex")

      view |> form("#sound-form", %{sound: "entity.creeper.primed"}) |> render_submit()

      assert_receive {:effect, :sound, "entity.creeper.primed"}
    end

    test "the boss bar form broadcasts the bar, and off removes it", %{conn: conn} do
      view = panel(conn, ["Alex"])
      listen_to("Alex")

      view
      |> form("#bar-form", %{title: "Boss", percent: "60", color: "red"})
      |> render_submit()

      assert_receive {:effect, :bar, %{title: "Boss", health: 0.6, color: :red}}

      view |> element("#bar-off") |> render_click()
      assert_receive {:effect, :bar, :off}
    end

    test "the watch form broadcasts the effect", %{conn: conn} do
      view = panel(conn, ["Alex"])
      listen_to("Alex")

      view |> form("#watch-form", %{entity: "zombie", radius: "12"}) |> render_submit()

      assert_receive {:effect, :watch, {"zombie", 12}}
    end

    test "an empty title sends nothing and shows an error", %{conn: conn} do
      view = panel(conn, ["Alex"])
      listen_to("Alex")

      html = view |> form("#title-form", %{text: "  "}) |> render_submit()

      refute_receive {:effect, _, _}
      assert html =~ "Write a title first"
    end

    test "an unknown sound sends nothing and shows an error", %{conn: conn} do
      view = panel(conn, ["Alex"])
      listen_to("Alex")

      html = view |> form("#sound-form", %{sound: "entity.dragon_cat.meow"}) |> render_submit()

      refute_receive {:effect, _, _}
      assert html =~ "Unknown sound"
    end

    test "a percent out of 0 to 100 sends nothing and shows an error", %{conn: conn} do
      view = panel(conn, ["Alex"])
      listen_to("Alex")

      html =
        view
        |> form("#bar-form", %{title: "Boss", percent: "150", color: "red"})
        |> render_submit()

      refute_receive {:effect, _, _}
      assert html =~ "The percent goes from 0 to 100"
    end
  end

  describe "with a real player" do
    setup :listen_server

    test "lists the watches of the player, and unwatch broadcasts the effect",
         %{conn: conn, listen: listen} do
      {:ok, view, _html} = live(conn, "/")
      {_client, _server, pid} = join(listen, "Alex")
      players_told(view)
      listen_to("Alex")
      Phoenix.PubSub.broadcast(Hotblock.PubSub, "player:Alex", {:effect, :watch, {"zombie", 10}})
      # Once the connection answers, it has handled the watch
      :sys.get_state(pid)

      refresh(view)
      assert has_element?(view, "#unwatch-zombie")

      view |> element("#unwatch-zombie") |> render_click()

      assert_receive {:effect, :unwatch, "zombie"}
    end
  end

  describe "map" do
    test "a tap on the map spawns the chosen entity at that offset", %{conn: conn} do
      view = panel(conn, ["Alex"])
      listen_to("Alex")

      view |> form("#spawn-form", %{entity: "creeper"}) |> render_change()
      view |> element("#map") |> render_hook("spawn", %{"dx" => 2, "dz" => -3.5})

      assert_receive {:effect, :spawn, {"creeper", {2.0, -3.5}}}
    end

    test "a tap outside the map spawns nothing", %{conn: conn} do
      view = panel(conn, ["Alex"])
      listen_to("Alex")

      html = view |> element("#map") |> render_hook("spawn", %{"dx" => 10_000_000, "dz" => 0})

      refute_receive {:effect, _, _}
      assert html =~ "Tap inside the map"
    end

    test "zombie is the entity chosen at first", %{conn: conn} do
      view = panel(conn, ["Alex"])
      listen_to("Alex")

      view |> element("#map") |> render_hook("spawn", %{"dx" => 1.0, "dz" => 1.0})

      assert_receive {:effect, :spawn, {"zombie", {1.0, 1.0}}}
    end
  end

  describe "map with a real player" do
    setup :listen_server

    test "shows the player, and keeps the last map while the connection is suspended",
         %{conn: conn, listen: listen} do
      {:ok, view, _html} = live(conn, "/")
      {client, server, pid} = join(listen, "Alex")
      players_told(view)
      to_play(client, server)
      move(client, server, {0.0, 64.0, 0.0})
      # Once the connection answers, it has read the position
      :sys.get_state(pid)

      refresh(view)
      assert has_element?(view, "#map .player")

      # The snapshot times out after 200 ms, and the page keeps the last map
      :ok = :sys.suspend(pid)
      refresh(view)
      assert has_element?(view, "#map .player")
      :ok = :sys.resume(pid)
    end
  end

  describe "admin" do
    @admin "/admin?token=test-token"

    test "/admin without the token is a 404", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, "/admin") end
    end

    test "/admin with a wrong token is a 404", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, "/admin?token=nope") end
    end

    test "with no admin token configured, /admin is always a 404", %{conn: conn} do
      for token <- [nil, ""] do
        Application.put_env(:hotblock, :admin_token, token)

        assert_error_sent 404, fn -> get(conn, "/admin?token=") end
        assert_error_sent 404, fn -> get(conn, "/admin?token=test-token") end
      end
    after
      Application.put_env(:hotblock, :admin_token, "test-token")
    end

    test "the token is hidden in the logs" do
      assert Phoenix.Logger.filter_values(%{"token" => "test-token"}) ==
               %{"token" => "[FILTERED]"}
    end

    test "/ has no admin controls", %{conn: conn} do
      view = panel(conn, ["Alex"])

      refute has_element?(view, "#kick-form")
      refute has_element?(view, "#crash")
    end

    test "/admin with the token has kick and crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, @admin)
      send(view.pid, {:player_joined, "Alex"})

      assert has_element?(view, "#kick-form")
      assert has_element?(view, "#crash")
    end

    test "kick sends the reason to the player's connection", %{conn: conn} do
      # The test process stands in for Alex's connection
      {:ok, _} = Registry.register(Hotblock.PlayerRegistry, "Alex", nil)
      {:ok, view, _html} = live(conn, @admin)

      view |> form("#kick-form", %{reason: "Bye"}) |> render_submit()

      assert_receive {:kick, "Bye"}
    end

    test "kick without a reason uses a default one", %{conn: conn} do
      {:ok, _} = Registry.register(Hotblock.PlayerRegistry, "Alex", nil)
      {:ok, view, _html} = live(conn, @admin)

      view |> form("#kick-form", %{reason: " "}) |> render_submit()

      assert_receive {:kick, "Kicked from the Hotblock panel"}
    end
  end

  describe "admin with real players" do
    setup :listen_server

    test "crash kills only that player's connection", %{conn: conn, listen: listen} do
      {_alex_client, _alex_server, alex} = join(listen, "Alex")
      {steve_client, steve_server, steve} = join(listen, "Steve")
      ref = Process.monitor(alex)
      {:ok, view, _html} = live(conn, @admin)

      view |> element("#crash") |> render_click()

      assert_receive {:DOWN, ^ref, :process, ^alex, :killed}
      assert Process.alive?(steve)

      :ok = :gen_tcp.send(steve_client, <<0x01, 0xAA>>)
      assert {:ok, <<0x01, 0xAA>>} = :gen_tcp.recv(steve_server, 2, 1000)
    end
  end

  describe "limit per visitor" do
    setup do
      Application.put_env(:hotblock, :effect_cooldown_ms, 60_000)
      on_exit(fn -> Application.put_env(:hotblock, :effect_cooldown_ms, 0) end)
    end

    test "a visitor can't send another effect before the limit", %{conn: conn} do
      view = panel(conn, ["Alex"])
      listen_to("Alex")

      view |> element("#weather-rain") |> render_click()
      html = view |> element("#weather-clear") |> render_click()

      assert_receive {:effect, :weather, :rain}
      refute_receive {:effect, :weather, :clear}
      assert html =~ "Wait a moment"
    end

    test "the limit also counts taps on the map", %{conn: conn} do
      view = panel(conn, ["Alex"])
      listen_to("Alex")

      view |> element("#weather-rain") |> render_click()
      view |> element("#map") |> render_hook("spawn", %{"dx" => 1, "dz" => 1})

      assert_receive {:effect, :weather, :rain}
      refute_receive {:effect, :spawn, _}
    end

    test "the admin page has no limit", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin?token=test-token")
      send(view.pid, {:player_joined, "Alex"})
      listen_to("Alex")

      view |> element("#weather-rain") |> render_click()
      view |> element("#weather-clear") |> render_click()

      assert_receive {:effect, :weather, :rain}
      assert_receive {:effect, :weather, :clear}
    end
  end

  describe "unexpected events" do
    test "admin events on / do nothing and the page keeps working", %{conn: conn} do
      view = panel(conn, ["Alex"])

      assert render_hook(view, "crash", %{}) =~ "not available here"
      assert render_hook(view, "kick", %{"reason" => "x"}) =~ "not available here"
      assert Process.alive?(view.pid)
    end

    test "events with wrong values do nothing and the page keeps working", %{conn: conn} do
      view = panel(conn, ["Alex"])
      listen_to("Alex")

      render_hook(view, "spawn", %{"dx" => "a", "dz" => 0})
      render_hook(view, "weather", %{"weather" => "snow"})

      refute_receive {:effect, _, _}
      assert Process.alive?(view.pid)
    end

    test "selecting a player who is not online keeps the selection", %{conn: conn} do
      view = panel(conn, ["Alex"])

      render_hook(view, "select", %{"name" => "Ghost"})

      assert has_element?(view, "#players [data-player=Alex][aria-current=true]")
    end
  end

  # The page redraws every time the map changes. LiveView puts back the
  # server's value in every input that does not have the focus, and these
  # forms keep their values only in the browser, so they must not be patched.
  test "the forms that keep what was typed are not touched when the page redraws",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin?token=test-token")
    send(view.pid, {:player_joined, "Alex"})

    for form <- ~w(title-form actionbar-form sound-form watch-form kick-form) do
      assert has_element?(view, "##{form}[phx-update=ignore]"), "#{form} is patched"
    end
  end

  test "the entity and sound lists come from minecraft-data", %{conn: conn} do
    view = panel(conn, ["Alex"])

    assert has_element?(view, "#watch-form option[value=zombie]", "Zombie")
    assert has_element?(view, "#sounds option[value='entity.creeper.primed']")
  end
end
