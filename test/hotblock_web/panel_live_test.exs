defmodule HotblockWeb.PanelLiveTest do
  # async: false because the list of players is global: other tests connect
  # real players through the proxy
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Hotblock.ProxyHelpers, only: [listen_server: 1]

  @endpoint HotblockWeb.Endpoint

  setup do
    wait_until_nobody_is_online()
    %{conn: build_conn()}
  end

  # Players from other tests may still be closing
  defp wait_until_nobody_is_online(tries \\ 50) do
    if Hotblock.Players.list() != [] and tries > 0 do
      Process.sleep(20)
      wait_until_nobody_is_online(tries - 1)
    end
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
      {_client, _server, _pid} = Hotblock.ProxyHelpers.join(listen, "Alex")
      listen_to("Alex")
      Phoenix.PubSub.broadcast(Hotblock.PubSub, "player:Alex", {:effect, :watch, {"zombie", 10}})

      # The page asks the connection for its state a few times a second
      assert eventually(fn -> has_element?(view, "#unwatch-zombie") end)

      view |> element("#unwatch-zombie") |> render_click()

      assert_receive {:effect, :unwatch, "zombie"}
    end
  end

  defp eventually(fun, tries \\ 40) do
    cond do
      fun.() ->
        true

      tries > 0 ->
        Process.sleep(25)
        eventually(fun, tries - 1)

      true ->
        false
    end
  end

  test "the entity and sound lists come from minecraft-data", %{conn: conn} do
    view = panel(conn, ["Alex"])

    assert has_element?(view, "#watch-form option[value=zombie]", "Zombie")
    assert has_element?(view, "#sounds option[value='entity.creeper.primed']")
  end
end
