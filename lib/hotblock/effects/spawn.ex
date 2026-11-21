defmodule Hotblock.Effects.Spawn do
  alias Hotblock.Protocol.Encoder.Clientbound
  alias Hotblock.Protocol.Encoder.Serverbound
  alias Hotblock.Entities

  def position({x, y, z}, yaw, distance, direction) do
    angle = (yaw + turn(direction)) * :math.pi() / 180
    {x - :math.sin(angle) * distance, y, z + :math.cos(angle) * distance}
  end

  defp turn(:front), do: 0
  defp turn(:right), do: 90
  defp turn(:behind), do: 180
  defp turn(:left), do: -90

  def packets(_name, _distance, _direction, nil, _yaw), do: position_unknown()
  def packets(_name, _distance, _direction, _player_position, nil), do: position_unknown()

  def packets(name, distance, direction, player_position, yaw) do
    if Entities.known?(name) do
      {x, y, z} = position(player_position, yaw, distance, direction)
      command = "summon minecraft:#{name} #{format(x)} #{format(y)} #{format(z)}"
      {:server, Serverbound.chat_command(command)}
    else
      {:client, Clientbound.system_chat("Unknown entity: #{name}")}
    end
  end

  defp position_unknown do
    {:client, Clientbound.system_chat("Your position is not known yet, move a bit and try again")}
  end

  defp format(value), do: :erlang.float_to_binary(Float.round(value, 2) + 0.0, decimals: 2)
end
