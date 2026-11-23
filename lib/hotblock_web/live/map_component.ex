defmodule HotblockWeb.MapComponent do
  @moduledoc """
  A top-down map around the player, drawn as SVG. North is up. The map's
  units are blocks: the player is at 0, 0, x grows to the right (east) and z
  grows down (south), like in the game, so an offset in the world is the same
  offset on the map.
  """
  use Phoenix.Component

  alias Hotblock.Entities

  attr :snapshot, :map, default: nil, doc: "from Connection.snapshot/1, or nil"
  attr :radius, :integer, default: 24, doc: "how many blocks the map shows around the player"

  def map(%{snapshot: %{position: {_, _, _}}} = assigns) do
    assigns =
      assign(assigns,
        lines: grid_lines(assigns.radius),
        entities: nearby(assigns.snapshot, assigns.radius),
        watches: Enum.sort(assigns.snapshot.watches),
        # The arrow is drawn pointing up (north), and yaw 0 is south
        heading: number((assigns.snapshot.yaw || 0) + 180)
      )

    ~H"""
    <svg
      id="map"
      class="map"
      viewBox={"#{-@radius} #{-@radius} #{@radius * 2} #{@radius * 2}"}
      phx-hook="MapTap"
      role="img"
      aria-label="Map around the player. Tap a spot to spawn there."
    >
      <line :for={v <- @lines} class="grid" x1={v} y1={-@radius} x2={v} y2={@radius} />
      <line :for={v <- @lines} class="grid" x1={-@radius} y1={v} x2={@radius} y2={v} />

      <circle :for={{name, radius} <- @watches} class="watch" cx="0" cy="0" r={radius}>
        <title>Watching {name} within {radius} blocks</title>
      </circle>

      <circle
        :for={entity <- @entities}
        class={"entity #{entity.category}"}
        cx={entity.x}
        cy={entity.z}
        r="0.8"
      >
        <title>{entity.type}</title>
      </circle>

      <g class="player" transform={"rotate(#{@heading})"}>
        <polygon points="0,-1.8 1.3,1.4 0,0.6 -1.3,1.4" />
      </g>
    </svg>
    """
  end

  # Without a position there is nothing to draw around
  def map(assigns) do
    ~H"""
    <div id="map" class="map map-waiting" phx-hook="MapTap">
      <div class="empty-block"></div>
      <p>Move a bit in game to see the map.</p>
    </div>
    """
  end

  defp grid_lines(radius), do: Enum.filter(-radius..radius, &(rem(&1, 4) == 0))

  # The entities within the radius, as offsets from the player
  defp nearby(%{position: {px, _, pz}, entities: entities}, radius) do
    for %{type: type, position: {x, _, z}} <- entities,
        dx = x - px,
        dz = z - pz,
        dx * dx + dz * dz <= radius * radius do
      %{type: type, category: Entities.category(type), x: number(dx), z: number(dz)}
    end
  end

  # Short numbers for the SVG: 3.0 is written as 3, others with two decimals
  # at most
  defp number(value) do
    rounded = Float.round(value * 1.0, 2)

    if rounded == trunc(rounded) do
      Integer.to_string(trunc(rounded))
    else
      Float.to_string(rounded)
    end
  end
end
