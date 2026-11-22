defmodule Hotblock.Players do
  @moduledoc """
  Tells the panel when players join and leave, on the PubSub topic "players"
  """
  use GenServer

  @registry Hotblock.PlayerRegistry
  @topic "players"

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  # The names of the players online, sorted
  def list do
    @registry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.sort()
  end

  @impl true
  def init(nil), do: {:ok, %{}}

  # The state is %{monitor ref => player name}
  @impl true
  def handle_info({:register, @registry, name, pid, _value}, names) do
    ref = Process.monitor(pid)
    broadcast({:player_joined, name})
    {:noreply, Map.put(names, ref, name)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, names) do
    {name, names} = Map.pop(names, ref)
    broadcast({:player_left, name})
    {:noreply, names}
  end

  # Connections never unregister, they just end
  def handle_info({:unregister, @registry, _name, _pid}, names), do: {:noreply, names}

  defp broadcast(message), do: Phoenix.PubSub.broadcast(Hotblock.PubSub, @topic, message)
end
