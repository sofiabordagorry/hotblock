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

  # The state is %{monitor ref => player name}.
  # If this process restarts, it monitors again the players who are already
  # online, so it still hears when they leave. At boot it starts before the
  # Registry, so there is nobody yet.
  @impl true
  def init(nil) do
    names = for {name, pid} <- online(), into: %{}, do: {Process.monitor(pid), name}
    {:ok, names}
  end

  defp online do
    Registry.select(@registry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
  rescue
    ArgumentError -> []
  end

  @impl true
  def handle_info({:register, @registry, name, pid, _value}, names) do
    ref = Process.monitor(pid)
    broadcast({:player_joined, name})
    {:noreply, Map.put(names, ref, name)}
  end

  # When a player reconnects quickly, the new connection can register before
  # this hears that the old one ended. Then the player is still online.
  def handle_info({:DOWN, ref, :process, pid, _reason}, names) do
    {name, names} = Map.pop(names, ref)

    case Registry.lookup(@registry, name) do
      [{other, _}] when other != pid -> :ok
      _ -> broadcast({:player_left, name})
    end

    {:noreply, names}
  end

  # Connections never unregister, they just end
  def handle_info({:unregister, @registry, _name, _pid}, names), do: {:noreply, names}

  defp broadcast(message), do: Phoenix.PubSub.broadcast(Hotblock.PubSub, @topic, message)
end
