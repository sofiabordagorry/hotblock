defmodule Hotblock.Telemetry do
  @moduledoc """
  The proxy's :telemetry events, shown in LiveDashboard at /dashboard:

    * [:hotblock, :connections] - %{count: players connected}
    * [:hotblock, :packets] - %{from_client: n, from_server: n}, the packets
      since the last measurement
    * [:hotblock, :reload, :start | :stop] - from Hotblock.Reload, with the
      modules and, on stop, the duration and the result

  The connections count their packets in shared counters instead of emitting
  an event per packet, which keeps the packet path cheap. A poller calls the
  measure functions every second (HotblockWeb.Telemetry).
  """

  @directions [from_client: 1, from_server: 2]

  # Called once when the app starts, before any connection
  def setup do
    :persistent_term.put(__MODULE__, :counters.new(length(@directions), [:write_concurrency]))
  end

  def packet(direction), do: :counters.add(counters(), Keyword.fetch!(@directions, direction), 1)

  # Takes the counts and subtracts them, so packets counted meanwhile are kept
  # for the next measurement
  def measure_packets do
    ref = counters()

    counts =
      for {direction, index} <- @directions, into: %{} do
        count = :counters.get(ref, index)
        :counters.sub(ref, index, count)
        {direction, count}
      end

    :telemetry.execute([:hotblock, :packets], counts, %{})
  end

  def measure_connections do
    %{active: count} = DynamicSupervisor.count_children(Hotblock.ConnectionSupervisor)
    :telemetry.execute([:hotblock, :connections], %{count: count}, %{})
  end

  defp counters, do: :persistent_term.get(__MODULE__)
end
