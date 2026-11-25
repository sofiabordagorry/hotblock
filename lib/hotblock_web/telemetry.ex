defmodule HotblockWeb.Telemetry do
  # Measures the proxy every second and lists the metrics LiveDashboard shows
  use Supervisor

  import Telemetry.Metrics

  def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller,
       measurements: [
         {Hotblock.Telemetry, :measure_connections, []},
         {Hotblock.Telemetry, :measure_packets, []}
       ],
       period: Application.get_env(:hotblock, :telemetry_period, 1_000),
       name: :hotblock_poller}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      last_value("hotblock.connections.count", description: "Players connected"),
      last_value("hotblock.packets.from_client",
        description: "Packets per second from the clients"
      ),
      last_value("hotblock.packets.from_server",
        description: "Packets per second from the server"
      ),
      summary("hotblock.reload.stop.duration",
        unit: {:native, :millisecond},
        tags: [:result],
        description: "Reloads, by result"
      )
    ]
  end
end
