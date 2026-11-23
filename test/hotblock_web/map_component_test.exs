defmodule HotblockWeb.MapComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias HotblockWeb.MapComponent

  # The player at x 10, z 20, facing south (yaw 0)
  @snapshot %{
    position: {10.0, 64.0, 20.0},
    yaw: 0.0,
    entities: [],
    watches: %{},
    boss_bar: nil
  }

  defp map(snapshot), do: render_component(&MapComponent.map/1, snapshot: snapshot, radius: 24)

  test "the arrow points where the player looks" do
    # yaw 0 is south, down on the map; the arrow is drawn pointing up
    assert map(@snapshot) =~ ~s|transform="rotate(180)"|
    # yaw 90 is west, left on the map
    assert map(%{@snapshot | yaw: 90.0}) =~ ~s|transform="rotate(270)"|
  end

  test "an entity is a dot at its offset from the player, coloured by category" do
    zombie = %{type: "zombie", position: {13.0, 64.0, 24.0}}
    html = map(%{@snapshot | entities: [zombie]})

    assert html =~ ~r/<circle[^>]*class="entity hostile"[^>]*cx="3"[^>]*cy="4"/
  end

  test "an entity outside the radius is not drawn" do
    far = %{type: "pig", position: {40.0, 64.0, 20.0}}

    refute map(%{@snapshot | entities: [far]}) =~ "entity passive"
  end

  test "a watch is a circle around the player with its radius" do
    assert map(%{@snapshot | watches: %{"zombie" => 10}}) =~
             ~r/<circle[^>]*class="watch"[^>]*r="10"/
  end

  test "before the position is known, it asks to move in game" do
    assert map(%{@snapshot | position: nil}) =~ "Move a bit in game"
    assert map(nil) =~ "Move a bit in game"
  end
end
