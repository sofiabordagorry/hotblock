defmodule Hotblock.PlayerTest do
  # async: false because the proxy listens on a fixed port
  use ExUnit.Case, async: false

  alias Hotblock.Protocol.{Encoder, Types}
  alias Hotblock.Rules

  @proxy_port 25565
  @opts [:binary, packet: :raw, active: false]

  setup do
    server_port = Application.fetch_env!(:hotblock, :server_port)
    {:ok, listen} = :gen_tcp.listen(server_port, @opts ++ [reuseaddr: true])
    on_exit(fn -> :gen_tcp.close(listen) end)
    %{listen: listen}
  end

  # Connects a fake client and a fake server through the proxy, and logs the
  # client in with the given name: a handshake with intent 2 (login), then
  # Login Start
  defp join(listen, name) do
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

    {client, server}
  end

  # The Registry is updated by the connection process, so the test waits for it
  defp lookup(name, tries \\ 20) do
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
  defp free?(name, tries \\ 20) do
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

  test "registers the connection under the player name", %{listen: listen} do
    {_client, _server} = join(listen, "Alex")

    assert [{pid, _}] = lookup("Alex")
    assert pid in connections()
  end

  test "a broadcast to player:<name> shows a title in that player's game", %{listen: listen} do
    {client, _server} = join(listen, "Steve")
    [_registered] = lookup("Steve")

    Phoenix.PubSub.broadcast(Hotblock.PubSub, "player:Steve", {:effect, :title, "hi"})

    {:ok, [{:client, title}], _state} = Rules.handle_effect(:title, "hi", %{})
    assert {:ok, ^title} = :gen_tcp.recv(client, byte_size(title), 1000)
  end

  test "a broadcast to another player does not reach this one", %{listen: listen} do
    {client, _server} = join(listen, "Notch")
    [_registered] = lookup("Notch")

    Phoenix.PubSub.broadcast(Hotblock.PubSub, "player:Herobrine", {:effect, :title, "hi"})

    assert {:error, :timeout} = :gen_tcp.recv(client, 0, 200)
  end

  test "the name is free again once the player disconnects", %{listen: listen} do
    {client, _server} = join(listen, "Jeb")
    [{pid, _}] = lookup("Jeb")
    ref = Process.monitor(pid)

    :ok = :gen_tcp.close(client)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1000

    assert free?("Jeb")
  end

  defp connections do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(Hotblock.ConnectionSupervisor),
        is_pid(pid),
        do: pid
  end
end
