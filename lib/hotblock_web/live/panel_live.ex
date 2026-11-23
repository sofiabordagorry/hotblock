defmodule HotblockWeb.PanelLive do
  @moduledoc """
  The control panel: the players online and, for the selected one, a control
  for every effect. Each control broadcasts {:effect, effect, arg} on the
  player's topic, and the connection applies it through Rules.
  """
  use Phoenix.LiveView

  alias Hotblock.{Commands, Connection, Entities, Players}
  alias Hotblock.Effects.Sound
  alias HotblockWeb.MapComponent

  # How many blocks the map shows around the player
  @map_radius 24

  # How often the page asks the selected player's connection for its state
  @refresh_ms 250

  @impl true
  def mount(params, _session, socket) do
    admin? = socket.assigns.live_action == :admin

    # Without the right token, /admin looks like it does not exist
    if admin? and not valid_token?(params["token"]), do: raise(HotblockWeb.NotFoundError)

    if connected?(socket) do
      # Subscribes before listing, so nobody who joins in between is missed
      Phoenix.PubSub.subscribe(Hotblock.PubSub, "players")
      send(self(), :refresh)
    end

    players = Players.list()

    {:ok,
     assign(socket,
       players: players,
       selected: List.first(players),
       snapshot: nil,
       admin?: admin?,
       entities: Entities.spawnable(),
       sounds: Sound.names(),
       bar_colors: Commands.bar_colors(),
       bar: %{"title" => "", "percent" => "50", "color" => "red"},
       spawn_entity: "zombie",
       map_radius: @map_radius
     )}
  end

  defp valid_token?(token) when is_binary(token) do
    expected = Application.get_env(:hotblock, :admin_token)
    is_binary(expected) and expected != "" and Plug.Crypto.secure_compare(token, expected)
  end

  defp valid_token?(_token), do: false

  # Players joining and leaving

  @impl true
  def handle_info({:player_joined, name}, socket) do
    players = Enum.sort(Enum.uniq([name | socket.assigns.players]))
    {:noreply, socket |> assign(players: players) |> select(socket.assigns.selected || name)}
  end

  def handle_info({:player_left, name}, socket) do
    players = List.delete(socket.assigns.players, name)
    socket = assign(socket, players: players)

    if socket.assigns.selected == name do
      {:noreply, select(socket, List.first(players))}
    else
      {:noreply, socket}
    end
  end

  # Asks the selected player's connection for its state, and asks again soon.
  # While the connection can't answer, like during a reload, the last state
  # stays on the page.
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_ms)

    case snapshot(socket.assigns.selected) do
      :unavailable -> {:noreply, socket}
      snapshot -> {:noreply, assign(socket, snapshot: snapshot)}
    end
  end

  defp snapshot(nil), do: nil

  defp snapshot(name) do
    case Registry.lookup(Hotblock.PlayerRegistry, name) do
      [{pid, _}] -> Connection.snapshot(pid)
      [] -> nil
    end
  end

  defp select(socket, name) do
    if name == socket.assigns.selected do
      socket
    else
      assign(socket, selected: name, snapshot: nil)
    end
  end

  # The controls

  @impl true
  def handle_event("select", %{"name" => name}, socket) do
    if name in socket.assigns.players do
      {:noreply, select(socket, name)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("spawn_entity", %{"entity" => entity}, socket) do
    {:noreply, assign(socket, spawn_entity: entity)}
  end

  # A tap on the map, as an offset in blocks from the player. Only taps
  # inside the map count.
  def handle_event("spawn", %{"dx" => dx, "dz" => dz}, socket)
      when is_number(dx) and is_number(dz) do
    if dx * dx + dz * dz <= @map_radius * @map_radius do
      entity = socket.assigns.spawn_entity

      {:noreply,
       send_effect(socket, :spawn, {entity, {dx * 1.0, dz * 1.0}}, display_name(entity))}
    else
      {:noreply, error(socket, "Tap inside the map")}
    end
  end

  def handle_event("title", %{"text" => text}, socket) do
    case String.trim(text) do
      "" -> {:noreply, error(socket, "Write a title first")}
      text -> {:noreply, send_effect(socket, :title, text, "Title")}
    end
  end

  def handle_event("actionbar", %{"text" => text}, socket) do
    case String.trim(text) do
      "" -> {:noreply, error(socket, "Write a text first")}
      text -> {:noreply, send_effect(socket, :actionbar, text, "Action bar")}
    end
  end

  def handle_event("weather", %{"weather" => weather}, socket)
      when weather in ["clear", "rain", "thunder"] do
    {:noreply, send_effect(socket, :weather, String.to_existing_atom(weather), "Weather")}
  end

  def handle_event("sound", %{"sound" => sound}, socket) do
    sound = String.trim(sound)

    if Sound.known?(sound) do
      {:noreply, send_effect(socket, :sound, sound, "Sound")}
    else
      {:noreply, error(socket, "Unknown sound: #{sound}")}
    end
  end

  # Keeps what the bar form has, for the preview
  def handle_event("bar_change", params, socket) do
    {:noreply, assign(socket, bar: Map.take(params, ["title", "percent", "color"]))}
  end

  def handle_event("bar", %{"title" => title, "percent" => percent, "color" => color}, socket) do
    title = String.trim(title)

    cond do
      title == "" ->
        {:noreply, error(socket, "Write the bar's text first")}

      percent(percent) == :error ->
        {:noreply, error(socket, "The percent goes from 0 to 100")}

      color not in socket.assigns.bar_colors ->
        {:noreply, error(socket, "Unknown color: #{color}")}

      true ->
        bar = %{
          title: title,
          health: percent(percent) / 100,
          color: String.to_existing_atom(color)
        }

        {:noreply, send_effect(socket, :bar, bar, "Boss bar")}
    end
  end

  def handle_event("bar_off", _params, socket) do
    {:noreply, send_effect(socket, :bar, :off, "Boss bar removal")}
  end

  def handle_event("watch", %{"entity" => entity, "radius" => radius}, socket) do
    case Integer.parse(radius) do
      {radius, ""} when radius > 0 ->
        if Entities.known?(entity) do
          {:noreply, send_effect(socket, :watch, {entity, radius}, "Watch")}
        else
          {:noreply, error(socket, "Unknown entity: #{entity}")}
        end

      _ ->
        {:noreply, error(socket, "The radius must be a whole number above 0")}
    end
  end

  def handle_event("unwatch", %{"entity" => entity}, socket) do
    {:noreply, send_effect(socket, :unwatch, entity, "Unwatch")}
  end

  # Admin only

  def handle_event("kick", %{"reason" => reason}, %{assigns: %{admin?: true}} = socket) do
    reason =
      case String.trim(reason) do
        "" -> "Kicked from the Hotblock panel"
        reason -> reason
      end

    with_connection(socket, fn pid, name ->
      Connection.kick(pid, reason)
      "#{name} was kicked"
    end)
  end

  # Kills the connection's process on purpose. The supervisor doesn't restart
  # it, and the other players' connections are separate processes, so they
  # keep playing.
  def handle_event("crash", _params, %{assigns: %{admin?: true}} = socket) do
    with_connection(socket, fn pid, name ->
      Process.exit(pid, :kill)
      "#{name}'s connection crashed. The others keep playing."
    end)
  end

  # Anything else: an admin action outside /admin, or values the controls
  # never send
  def handle_event(event, _params, socket) when event in ["kick", "crash"] do
    {:noreply, error(socket, "That is not available here")}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # Runs fun with the selected player's connection, and shows the message it
  # returns
  defp with_connection(socket, fun) do
    name = socket.assigns.selected

    case name && Registry.lookup(Hotblock.PlayerRegistry, name) do
      [{pid, _}] ->
        message = fun.(pid, name)
        {:noreply, socket |> clear_flash() |> put_flash(:info, message)}

      _ ->
        {:noreply, error(socket, "#{name || "Nobody"} is not connected")}
    end
  end

  defp percent(text) do
    case Integer.parse(String.trim(text)) do
      {percent, ""} when percent in 0..100 -> percent
      _ -> :error
    end
  end

  defp send_effect(%{assigns: %{selected: nil}} = socket, _effect, _arg, _what) do
    error(socket, "Nobody is selected")
  end

  defp send_effect(socket, effect, arg, what) do
    name = socket.assigns.selected
    Phoenix.PubSub.broadcast(Hotblock.PubSub, "player:" <> name, {:effect, effect, arg})

    socket
    |> clear_flash()
    |> put_flash(:info, "#{what} sent to #{name}")
  end

  defp error(socket, message), do: socket |> clear_flash() |> put_flash(:error, message)

  # The page
  #
  # The page redraws every time the map changes, and LiveView then puts back
  # the server's value in every input without the focus. The forms whose
  # values live only in the browser have phx-update="ignore", so what was
  # typed or chosen stays until it is sent.

  @impl true
  def render(assigns) do
    ~H"""
    <div class="app">
      <header class="top">
        <h1 class="logo">Hotblock <span :if={@admin?} class="badge">Admin</span></h1>
        <span class="online">
          <span class={["pulse", @players == [] && "off"]}></span>
          {length(@players)} online
        </span>
      </header>

      <div class="layout">
        <nav :if={@players != []} id="players" class="players" aria-label="Players">
          <button
            :for={name <- @players}
            type="button"
            class="player"
            data-player={name}
            aria-current={if name == @selected, do: "true"}
            phx-click="select"
            phx-value-name={name}
          >
            <span class="avatar">{String.first(name)}</span>
            <span class="name">{name}</span>
          </button>
        </nav>

        <main :if={@selected == nil} class="empty">
          <div class="empty-block"></div>
          <h2>Nobody is online</h2>
          <p>Join the server through the proxy, and the player shows up here.</p>
        </main>

        <main :if={@selected} class="controls">
          <section class="card map-card">
            <div class="map-head">
              <h2>Map</h2>
              <form id="spawn-form" phx-change="spawn_entity">
                <label>
                  <span>Tap to spawn</span>
                  <select name="entity">
                    <optgroup
                      :for={{label, category} <- [{"Hostile", :hostile}, {"Passive", :passive}]}
                      label={label}
                    >
                      <option
                        :for={entity <- @entities}
                        :if={entity.category == category}
                        value={entity.name}
                        selected={entity.name == @spawn_entity}
                      >
                        {entity.display_name}
                      </option>
                    </optgroup>
                  </select>
                </label>
              </form>
            </div>
            <MapComponent.map snapshot={@snapshot} radius={@map_radius} />
            <ul class="legend">
              <li><span class="key you"></span>You</li>
              <li><span class="key hostile"></span>Hostile</li>
              <li><span class="key passive"></span>Passive</li>
              <li><span class="key other"></span>Other</li>
              <li><span class="key watch"></span>Watch</li>
            </ul>
          </section>

          <div class="stack">
            <section class="card">
              <h2>Title</h2>
              <form id="title-form" class="row" phx-submit="title" phx-update="ignore">
                <input name="text" placeholder="Hello | a subtitle" autocomplete="off" />
                <button>Send</button>
              </form>
            </section>

            <section class="card">
              <h2>Action bar</h2>
              <form id="actionbar-form" class="row" phx-submit="actionbar" phx-update="ignore">
                <input name="text" placeholder="Text above the hotbar" autocomplete="off" />
                <button>Send</button>
              </form>
            </section>

            <section class="card">
              <h2>Weather</h2>
              <div class="weather">
                <button
                  :for={{weather, label} <- [clear: "Clear", rain: "Rain", thunder: "Thunder"]}
                  id={"weather-#{weather}"}
                  type="button"
                  class={["ghost", "weather-#{weather}"]}
                  phx-click="weather"
                  phx-value-weather={weather}
                >
                  <span class="weather-icon"></span>{label}
                </button>
              </div>
            </section>

            <section class="card">
              <h2>Sound</h2>
              <form id="sound-form" class="row" phx-submit="sound" phx-update="ignore">
                <input
                  name="sound"
                  list="sounds"
                  placeholder="Search, like creeper"
                  autocomplete="off"
                />
                <datalist id="sounds">
                  <option :for={sound <- @sounds} value={sound}></option>
                </datalist>
                <button>Play</button>
              </form>
            </section>

            <section class="card">
              <h2>Boss bar</h2>
              <div class={["bar-preview", "bar-#{@bar["color"]}"]}>
                <span class="bar-title">{bar_title(@bar["title"])}</span>
                <span class="bar-track">
                  <span class="bar-fill" style={"width: #{bar_width(@bar["percent"])}%"}></span>
                </span>
              </div>
              <form id="bar-form" class="bar-form" phx-submit="bar" phx-change="bar_change">
                <input name="title" placeholder="Text" value={@bar["title"]} autocomplete="off" />
                <input
                  name="percent"
                  type="number"
                  min="0"
                  max="100"
                  value={@bar["percent"]}
                  aria-label="Percent"
                />
                <select name="color" aria-label="Color">
                  <option :for={color <- @bar_colors} value={color} selected={color == @bar["color"]}>
                    {color}
                  </option>
                </select>
                <button>Show</button>
                <button id="bar-off" type="button" class="ghost" phx-click="bar_off">Off</button>
              </form>
            </section>

            <section class="card">
              <h2>Watch</h2>
              <form id="watch-form" class="row" phx-submit="watch" phx-update="ignore">
                <select name="entity" aria-label="Entity">
                  <optgroup
                    :for={{label, category} <- [{"Hostile", :hostile}, {"Passive", :passive}]}
                    label={label}
                  >
                    <option
                      :for={entity <- @entities}
                      :if={entity.category == category}
                      value={entity.name}
                      selected={entity.name == "zombie"}
                    >
                      {entity.display_name}
                    </option>
                  </optgroup>
                </select>
                <input name="radius" type="number" min="1" value="16" aria-label="Radius" />
                <button>Watch</button>
              </form>
              <ul :if={watches(@snapshot) != []} class="watches">
                <li :for={{entity, radius} <- watches(@snapshot)}>
                  <span>{entity} <small>within {radius} blocks</small></span>
                  <button
                    id={"unwatch-#{entity}"}
                    type="button"
                    class="ghost small"
                    phx-click="unwatch"
                    phx-value-entity={entity}
                  >
                    Unwatch
                  </button>
                </li>
              </ul>
            </section>

            <section :if={@admin?} class="card danger-zone">
              <h2>Admin</h2>
              <form id="kick-form" class="row" phx-submit="kick" phx-update="ignore">
                <input name="reason" placeholder="Reason for the kick" autocomplete="off" />
                <button class="danger">Kick</button>
              </form>
              <div class="crash">
                <p>Kills {@selected}'s connection on purpose. The others keep playing.</p>
                <button
                  id="crash"
                  type="button"
                  class="danger ghost"
                  phx-click="crash"
                  data-confirm={"Crash #{@selected}'s connection?"}
                >
                  Crash
                </button>
              </div>
            </section>
          </div>
        </main>
      </div>

      <div
        :if={message = Phoenix.Flash.get(@flash, :info) || Phoenix.Flash.get(@flash, :error)}
        id="toast"
        class={["toast", Phoenix.Flash.get(@flash, :error) && "error"]}
        role="status"
        phx-click="lv:clear-flash"
      >
        {message}
      </div>
    </div>
    """
  end

  defp display_name(name) do
    Enum.find_value(Entities.spawnable(), name, &(&1.name == name && &1.display_name))
  end

  defp watches(%{watches: watches}), do: Enum.sort(watches)
  defp watches(_snapshot), do: []

  defp bar_title(""), do: "Boss bar"
  defp bar_title(title), do: title

  defp bar_width(percent) do
    case percent(percent || "") do
      :error -> 0
      percent -> percent
    end
  end
end
