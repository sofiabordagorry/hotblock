defmodule Hotblock.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Hotblock.PubSub},
      {Registry, keys: :unique, name: Hotblock.PlayerRegistry},
      {DynamicSupervisor, name: Hotblock.ConnectionSupervisor, strategy: :one_for_one},
      Supervisor.child_spec({Task, fn -> Hotblock.Proxy.accept(25565) end}, restart: :permanent),
      HotblockWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Hotblock.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
