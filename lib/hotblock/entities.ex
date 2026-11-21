defmodule Hotblock.Entities do
  @external_resource "priv/minecraft_data/26.1/entities.json"
  @entities "priv/minecraft_data/26.1/entities.json"
            |> File.read!()
            |> JSON.decode!()

  # type id => name, to know what a spawned entity is
  @names Map.new(@entities, fn entity -> {entity["id"], entity["name"]} end)
  @known MapSet.new(@entities, fn entity -> entity["name"] end)

  def name(type_id), do: Map.get(@names, type_id)

  def known?(name) when is_binary(name), do: MapSet.member?(@known, name)
end
