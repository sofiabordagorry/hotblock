defmodule Hotblock.ProxyHelpers do
  # Helpers for the tests that connect a fake client and a fake server
  # through the proxy. Those tests use the proxy's fixed port, so they must
  # run with async: false.

  import ExUnit.Assertions

  alias Hotblock.Protocol.{Encoder, Types}

  @proxy_port 25565
  @opts [:binary, packet: :raw, active: false]

  # Listens on the server port the proxy connects to, as the fake server.
  # Meant for setup: returns %{listen: socket}.
  def listen_server(_context \\ %{}) do
    server_port = Application.fetch_env!(:hotblock, :server_port)
    {:ok, listen} = :gen_tcp.listen(server_port, @opts ++ [reuseaddr: true])
    ExUnit.Callbacks.on_exit(fn -> :gen_tcp.close(listen) end)
    %{listen: listen}
  end

  # Connects a fake client and a fake server through the proxy, and returns
  # the pid of the connection process the proxy started for them
  def connect(listen) do
    before = connections()
    {:ok, client} = :gen_tcp.connect(~c"localhost", @proxy_port, @opts)
    {:ok, server} = :gen_tcp.accept(listen, 1000)

    # The connection connects to the fake server inside its init, which runs
    # inside the supervisor's start_child. So once the supervisor answers this
    # call, the new connection is one of its children.
    :sys.get_state(Hotblock.ConnectionSupervisor)
    [pid] = connections() -- before

    {client, server, pid}
  end

  # Connects through the proxy and logs the client in with the given name: a
  # handshake with intent 2 (login), then Login Start
  def join(listen, name) do
    {client, server, pid} = connect(listen)

    handshake =
      <<0x00>> <>
        Types.encode_varint(775) <>
        Types.encode_string("localhost") <> <<25565::16>> <> Types.encode_varint(2)

    login_start = <<0x00>> <> Types.encode_string(name) <> <<0::128>>

    frames = Encoder.encode_frame(handshake) <> Encoder.encode_frame(login_start)
    :ok = :gen_tcp.send(client, frames)

    # The proxy still forwards both packets to the server
    {:ok, ^frames} = :gen_tcp.recv(server, byte_size(frames), 1000)

    # The connection registers the name in the same callback that forwards
    # Login Start. When it answers this call, that callback is done.
    :sys.get_state(pid)

    {client, server, pid}
  end

  # Moves a joined connection to the play state: Login Acknowledged, then
  # Acknowledge Finish Configuration, both with ID 0x03
  def to_play(client, server) do
    frames = Encoder.encode_frame(<<0x03>>) <> Encoder.encode_frame(<<0x03>>)
    :ok = :gen_tcp.send(client, frames)
    {:ok, ^frames} = :gen_tcp.recv(server, byte_size(frames), 1000)
    :ok
  end

  # Sends a position packet (0x1E: x, y, z, then the flags) from the client,
  # in play
  def move(client, server, {x, y, z}) do
    frame = Encoder.encode_frame(<<0x1E, x::float-64, y::float-64, z::float-64, 0>>)
    :ok = :gen_tcp.send(client, frame)
    {:ok, ^frame} = :gen_tcp.recv(server, byte_size(frame), 1000)
    :ok
  end

  # The Registry removes a name when it gets the exit of the process that
  # registered it, and nothing tells when that happened, so this one checks
  # again a few times
  def free?(name, tries \\ 20) do
    case Registry.lookup(Hotblock.PlayerRegistry, name) do
      [] ->
        true

      _ when tries > 0 ->
        Process.sleep(10)
        free?(name, tries - 1)

      _ ->
        false
    end
  end

  # Connections from other tests may still be closing. Waits for each one to
  # end.
  def wait_until_no_connections do
    for pid <- connections() do
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1000
    end

    :ok
  end

  def connections do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(Hotblock.ConnectionSupervisor),
        is_pid(pid),
        do: pid
  end
end
