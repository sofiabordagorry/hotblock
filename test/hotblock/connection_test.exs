defmodule Hotblock.ConnectionTest do
  # async: false because the proxy listens on a fixed port, and one test
  # reloads the Connection module
  use ExUnit.Case, async: false

  alias Hotblock.Connection
  alias Hotblock.Reload

  @proxy_port 25565
  @opts [:binary, packet: :raw, active: false]

  # The state before stats existed: no version and no stats
  @old_fields [:version, :stats]

  setup do
    server_port = Application.fetch_env!(:hotblock, :server_port)
    {:ok, listen} = :gen_tcp.listen(server_port, @opts ++ [reuseaddr: true])
    on_exit(fn -> :gen_tcp.close(listen) end)
    %{listen: listen}
  end

  # Connects a fake client and a fake server through the proxy, and returns
  # the pid of the connection process the proxy started for them
  defp connect(listen) do
    before = connections()
    {:ok, client} = :gen_tcp.connect(~c"localhost", @proxy_port, @opts)
    {:ok, server} = :gen_tcp.accept(listen, 1000)
    {client, server, new_connection(before)}
  end

  defp connections do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(Hotblock.ConnectionSupervisor),
        is_pid(pid),
        do: pid
  end

  defp new_connection(before, tries \\ 20) do
    case connections() -- before do
      [pid] ->
        pid

      [] when tries > 0 ->
        Process.sleep(10)
        new_connection(before, tries - 1)
    end
  end

  # Makes a running connection look like it was started by the code from
  # before this change
  defp make_old(pid), do: :sys.replace_state(pid, &Map.drop(&1, @old_fields))

  describe "migrate/1" do
    test "adds the version and the stats to a state from before they existed" do
      old = %{phase: :play, client_buffer: <<1, 2>>, position: {0.0, 64.0, 0.0}}

      assert Connection.migrate(old) ==
               Map.merge(old, %{version: 2, stats: %{from_client: 0, from_server: 0}})
    end

    test "leaves a state that is already on the current version as it is" do
      current = %{version: 2, stats: %{from_client: 5, from_server: 7}, phase: :play}

      assert Connection.migrate(current) == current
    end
  end

  describe "a connection" do
    test "starts with the current version and empty stats", %{listen: listen} do
      {_client, _server, pid} = connect(listen)

      state = :sys.get_state(pid)
      assert state.version == 2
      assert state.stats == %{from_client: 0, from_server: 0}
    end

    test "counts the packets in each direction", %{listen: listen} do
      {client, server, pid} = connect(listen)

      :ok = :gen_tcp.send(client, <<0x01, 0xAA, 0x01, 0xBB>>)
      {:ok, _} = :gen_tcp.recv(server, 4, 1000)
      :ok = :gen_tcp.send(server, <<0x01, 0xCC>>)
      {:ok, _} = :gen_tcp.recv(client, 2, 1000)

      assert :sys.get_state(pid).stats == %{from_client: 2, from_server: 1}
    end

    test "migrates its state with :sys.change_code and keeps working", %{listen: listen} do
      {client, server, pid} = connect(listen)
      make_old(pid)

      :ok = :sys.suspend(pid)
      :ok = :sys.change_code(pid, Connection, nil, nil)
      :ok = :sys.resume(pid)

      assert %{version: 2, stats: %{from_client: 0, from_server: 0}} = :sys.get_state(pid)

      :ok = :gen_tcp.send(client, <<0x01, 0xAA>>)
      assert {:ok, <<0x01, 0xAA>>} = :gen_tcp.recv(server, 2, 1000)
    end
  end

  describe "Reload.load_and_migrate/2" do
    test "loads the modules and migrates the state of running connections",
         %{listen: listen} do
      {client, server, pid} = connect(listen)
      make_old(pid)

      assert Reload.load_and_migrate([Connection], [pid]) == {:ok, [Connection]}
      assert %{version: 2, stats: %{from_client: 0, from_server: 0}} = :sys.get_state(pid)

      :ok = :gen_tcp.send(client, <<0x01, 0xAA>>)
      assert {:ok, <<0x01, 0xAA>>} = :gen_tcp.recv(server, 2, 1000)
    end

    test "leaves the connections running when the reload is refused", %{listen: listen} do
      {client, server, pid} = connect(listen)

      refused = {:error, {:old_code_in_use, [Connection]}}
      assert Reload.load_and_migrate([Connection], [pid], fn _ -> refused end) == refused

      :ok = :gen_tcp.send(client, <<0x01, 0xAA>>)
      assert {:ok, <<0x01, 0xAA>>} = :gen_tcp.recv(server, 2, 1000)
    end
  end
end
