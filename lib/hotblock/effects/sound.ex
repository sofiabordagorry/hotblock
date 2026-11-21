defmodule Hotblock.Effects.Sound do
  alias Hotblock.Protocol.Encoder

  @external_resource "priv/minecraft_data/26.1/sounds.json"
  @names "priv/minecraft_data/26.1/sounds.json"
         |> File.read!()
         |> JSON.decode!()
         |> MapSet.new(& &1["name"])

  def packets(_name, nil) do
    Encoder.system_chat("Your position is not known yet, move a bit and try again")
  end

  def packets(name, position) do
    if known?(name) do
      Encoder.sound_effect("minecraft:" <> name, position)
    else
      Encoder.system_chat("Unknown sound: #{name}")
    end
  end

  def known?(name) when is_binary(name), do: MapSet.member?(@names, name)
end
