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

  # Connects a fake client and a fake server through the proxy, and logs the
  # client in with the given name: a handshake with intent 2 (login), then
  # Login Start. Waits until the connection is registered.
  def join(listen, name) do
    {:ok, client} = :gen_tcp.connect(~c"localhost", @proxy_port, @opts)
    {:ok, server} = :gen_tcp.accept(listen, 1000)

    handshake =
      <<0x00>> <>
        Types.encode_varint(775) <>
        Types.encode_string("localhost") <> <<25565::16>> <> Types.encode_varint(2)

    login_start = <<0x00>> <> Types.encode_string(name) <> <<0::128>>

    frames = Encoder.encode_frame(handshake) <> Encoder.encode_frame(login_start)
    :ok = :gen_tcp.send(client, frames)

    # The proxy still forwards both packets to the server
    {:ok, ^frames} = :gen_tcp.recv(server, byte_size(frames), 1000)

    assert [{pid, _}] = lookup(name), "#{name} was not registered"
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

  # The Registry is updated by the connection process, so this waits for it
  def lookup(name, tries \\ 20) do
    case Registry.lookup(Hotblock.PlayerRegistry, name) do
      [] when tries > 0 ->
        Process.sleep(10)
        lookup(name, tries - 1)

      found ->
        found
    end
  end

  # The Registry removes the name when it sees the process exit, which can
  # happen just after the test sees it
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

  def connections do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(Hotblock.ConnectionSupervisor),
        is_pid(pid),
        do: pid
  end
end
