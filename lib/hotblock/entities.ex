defmodule Hotblock.Entities do
  @external_resource "priv/minecraft_data/26.1/entities.json"
  @entities "priv/minecraft_data/26.1/entities.json"
            |> File.read!()
            |> JSON.decode!()

  # type id => name, to know what a spawned entity is
  @names Map.new(@entities, fn entity -> {entity["id"], entity["name"]} end)
  @known MapSet.new(@entities, fn entity -> entity["name"] end)

  @categories %{"Hostile mobs" => :hostile, "Passive mobs" => :passive}

  # name => :hostile or :passive, only for mobs
  @mob_categories for entity <- @entities,
                      category = @categories[entity["category"]],
                      into: %{},
                      do: {entity["name"], category}

  # The mobs the panel can spawn, sorted by the name shown in the game
  @spawnable @entities
             |> Enum.filter(&Map.has_key?(@mob_categories, &1["name"]))
             |> Enum.map(fn entity ->
               %{
                 name: entity["name"],
                 display_name: entity["displayName"],
                 category: @mob_categories[entity["name"]]
               }
             end)
             |> Enum.sort_by(& &1.display_name)

  def name(type_id), do: Map.get(@names, type_id)

  def known?(name) when is_binary(name), do: MapSet.member?(@known, name)

  def spawnable, do: @spawnable

  # For the colours on the panel's map
  def category(name), do: Map.get(@mob_categories, name, :other)
end
