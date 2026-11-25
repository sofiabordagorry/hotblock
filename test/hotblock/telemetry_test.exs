defmodule Hotblock.TelemetryTest do
  # async: false because the packet counters are shared by every connection
  use ExUnit.Case, async: false

  import Hotblock.ProxyHelpers

  alias Hotblock.{Reload, Telemetry}

  setup :listen_server

  # The packet counters are shared, so each test starts with no connections
  # and the counters at zero
  setup do
    wait_until_no_connections()
    Hotblock.Telemetry.measure_packets()
    :ok
  end

  # Sends every event of these names to the test process
  defp listen(events) do
    test = self()
    id = make_ref()

    :telemetry.attach_many(
      id,
      events,
      fn name, measurements, metadata, _ -> send(test, {name, measurements, metadata}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)
  end

  describe "packets" do
    test "measure_packets/0 reports the packets since the last measurement, by direction" do
      listen([[:hotblock, :packets]])
      Telemetry.measure_packets()

      Telemetry.packet(:from_client)
      Telemetry.packet(:from_client)
      Telemetry.packet(:from_server)
      Telemetry.measure_packets()

      assert_receive {[:hotblock, :packets], %{from_client: 2, from_server: 1}, _}
    end

    test "starts again from zero after each measurement" do
      listen([[:hotblock, :packets]])
      Telemetry.packet(:from_server)
      Telemetry.measure_packets()

      Telemetry.measure_packets()

      assert_receive {[:hotblock, :packets], %{from_server: 1}, _}
      assert_receive {[:hotblock, :packets], %{from_client: 0, from_server: 0}, _}
    end

    test "a connection counts the packets it forwards", %{listen: listen} do
      listen([[:hotblock, :packets]])
      {client, server, _pid} = join(listen, "Counter")
      Telemetry.measure_packets()

      :ok = :gen_tcp.send(client, <<0x01, 0xAA>>)
      {:ok, _} = :gen_tcp.recv(server, 2, 1000)
      :ok = :gen_tcp.send(server, <<0x01, 0xBB>>)
      {:ok, _} = :gen_tcp.recv(client, 2, 1000)
      Telemetry.measure_packets()

      assert_receive {[:hotblock, :packets], %{from_client: 1, from_server: 1}, _}
    end
  end

  test "measure_connections/0 reports how many players are connected", %{listen: listen} do
    listen([[:hotblock, :connections]])
    join(listen, "Uno")
    join(listen, "Dos")

    Telemetry.measure_connections()

    # A connection from another test may still be closing, so at least these two
    assert_receive {[:hotblock, :connections], %{count: count}, _}
    assert count >= 2
  end

  describe "reloads" do
    test "a reload that loads modules reports its duration and the modules" do
      listen([[:hotblock, :reload, :stop]])

      Reload.load_and_migrate([Enum], [], fn modules -> {:ok, modules} end)

      assert_receive {[:hotblock, :reload, :stop], %{duration: duration},
                      %{result: :ok, modules: [Enum]}}

      assert is_integer(duration)
    end

    test "a refused reload is reported as refused" do
      listen([[:hotblock, :reload, :stop]])
      refused = {:error, {:old_code_in_use, [Enum]}}

      Reload.load_and_migrate([Enum], [], fn _ -> refused end)

      assert_receive {[:hotblock, :reload, :stop], _, %{result: :refused, modules: [Enum]}}
    end
  end
end
