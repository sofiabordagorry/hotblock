defmodule Hotblock.Effects.EntityWatch do
  alias Hotblock.Entities
  alias Hotblock.Protocol.Encoder

  # entities: %{id => %{type: "zombie", position: {x, y, z}}}
  # watches: %{"zombie" => 10}, the name and the radius
  # last_alerts: %{"zombie" => ms}, when the last alert for that type was sent
  defstruct entities: %{}, watches: %{}, last_alerts: %{}

  # How long to wait before warning again about the same type of entity
  @cooldown 5_000

  def new, do: %__MODULE__{}

  # Updates the entities with an event from Protocol.decode_entity_event/2.
  # Entities of an unknown type, or that were never spawned, are ignored.
  def track(watch, {:spawn, id, type_id, position}) do
    case Entities.name(type_id) do
      nil ->
        watch

      name ->
        entity = %{type: name, position: position}
        %{watch | entities: Map.put(watch.entities, id, entity)}
    end
  end

  def track(watch, {:move, id, {dx, dy, dz}}) do
    case Map.get(watch.entities, id) do
      %{position: {x, y, z}} = entity ->
        entity = %{entity | position: {x + dx, y + dy, z + dz}}
        %{watch | entities: Map.put(watch.entities, id, entity)}

      nil ->
        watch
    end
  end

  def track(watch, {:teleport, id, position}) do
    case Map.get(watch.entities, id) do
      nil ->
        watch

      entity ->
        entity = %{entity | position: position}
        %{watch | entities: Map.put(watch.entities, id, entity)}
    end
  end

  def track(watch, {:remove, ids}) do
    %{watch | entities: Map.drop(watch.entities, ids)}
  end

  # Starts watching a type of entity. Returns the reply for the chat and the
  # new state.
  def watch(watch, name, radius) do
    if Entities.known?(name) do
      watch = %{watch | watches: Map.put(watch.watches, name, radius)}
      {Encoder.system_chat("Watching #{name} within #{radius} blocks"), watch}
    else
      {Encoder.system_chat("Unknown entity: #{name}"), watch}
    end
  end

  # Stops watching a type of entity. Its cooldown is cleared too, so watching
  # it again warns right away.
  def unwatch(watch, name) do
    if Map.has_key?(watch.watches, name) do
      watch = %{
        watch
        | watches: Map.delete(watch.watches, name),
          last_alerts: Map.delete(watch.last_alerts, name)
      }

      {Encoder.system_chat("Stopped watching #{name}"), watch}
    else
      {Encoder.system_chat("You are not watching #{name}"), watch}
    end
  end

  # Returns the alerts to send, one per watched type that has an entity within
  # its radius, about the closest one. A type is not warned about again until
  # the cooldown has passed. `now` is in milliseconds.
  def alerts(watch, nil, _now), do: {<<>>, watch}

  def alerts(watch, player, now) do
    watch.watches
    |> Enum.sort()
    |> Enum.reduce({<<>>, watch}, fn {name, radius}, {packets, watch} ->
      distance = closest(watch, name, radius, player)

      if distance && cooled_down?(watch, name, now) do
        watch = %{watch | last_alerts: Map.put(watch.last_alerts, name, now)}
        {packets <> alert(name, distance, player), watch}
      else
        {packets, watch}
      end
    end)
  end

  # The distance to the closest entity of that type within the radius, or nil
  defp closest(watch, name, radius, player) do
    watch.entities
    |> Map.values()
    |> Enum.filter(fn entity -> entity.type == name end)
    |> Enum.map(fn entity -> distance(entity.position, player) end)
    |> Enum.filter(fn distance -> distance <= radius end)
    |> Enum.min(fn -> nil end)
  end

  defp distance({x1, y1, z1}, {x2, y2, z2}) do
    :math.sqrt((x1 - x2) ** 2 + (y1 - y2) ** 2 + (z1 - z2) ** 2)
  end

  defp cooled_down?(watch, name, now) do
    case Map.get(watch.last_alerts, name) do
      nil -> true
      last -> now - last >= @cooldown
    end
  end

  defp alert(name, distance, player) do
    blocks = round(distance)
    unit = if blocks == 1, do: "block", else: "blocks"

    Encoder.action_bar("#{name} #{blocks} #{unit} away!") <>
      Encoder.sound_effect("minecraft:block.note_block.pling", player)
  end
end
