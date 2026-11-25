defmodule Hotblock.CommandTreeTest do
  use ExUnit.Case, async: true

  alias Hotblock.CommandTree
  alias Hotblock.Protocol.Types

  # The root (node 0) with /gamemode, and the root index 0
  @gamemode <<0x05, 0x00>> <> Types.encode_string("gamemode")
  @payload Types.encode_varint(2) <> <<0x00, 0x01, 0x01>> <> @gamemode <> <<0x00>>

  defp decode(payload) do
    {:ok, count, rest} = Types.decode_varint(payload)
    {nodes, <<root_index>>} = decode_nodes(rest, count, [])
    {nodes, root_index}
  end

  defp decode_nodes(rest, 0, nodes), do: {Enum.reverse(nodes), rest}

  defp decode_nodes(<<flags, rest::binary>>, count, nodes) do
    {:ok, n, rest} = Types.decode_varint(rest)
    {children, rest} = decode_children(rest, n, [])

    {node, rest} =
      case Bitwise.band(flags, 0x03) do
        0 ->
          {%{type: :root}, rest}

        1 ->
          {:ok, name, rest} = Types.decode_string(rest)
          {%{type: :literal, name: name}, rest}

        2 ->
          {:ok, name, rest} = Types.decode_string(rest)
          {type, rest} = decode_parser(rest)
          {%{type: type, name: name}, rest}
      end

    node = Map.merge(node, %{children: children, executable: Bitwise.band(flags, 0x04) != 0})
    decode_nodes(rest, count - 1, [node | nodes])
  end

  defp decode_parser(<<5, 0, rest::binary>>), do: {:word, rest}
  defp decode_parser(<<5, 2, rest::binary>>), do: {:greedy, rest}

  defp decode_parser(<<3, flags, rest::binary>>) do
    {min, rest} = if Bitwise.band(flags, 1) != 0, do: take_int(rest), else: {nil, rest}
    {max, rest} = if Bitwise.band(flags, 2) != 0, do: take_int(rest), else: {nil, rest}
    {{:integer, min, max}, rest}
  end

  defp take_int(<<value::signed-32, rest::binary>>), do: {value, rest}

  defp decode_children(rest, 0, children), do: {Enum.reverse(children), rest}

  defp decode_children(rest, n, children) do
    {:ok, child, rest} = Types.decode_varint(rest)
    decode_children(rest, n - 1, [child | children])
  end

  defp children(nodes, node),
    do: Enum.map(node.children, &{Enum.at(nodes, &1).name, Enum.at(nodes, &1)})

  describe "add_commands/1" do
    test "keeps the server's commands as they were" do
      {:ok, payload} = CommandTree.add_commands(@payload)
      {nodes, 0} = decode(payload)

      assert %{type: :literal, name: "gamemode", executable: true} = Enum.at(nodes, 1)
      assert 1 in hd(nodes).children
    end

    test "adds the proxy's commands under the root" do
      {:ok, payload} = CommandTree.add_commands(@payload)
      {[root | _] = nodes, 0} = decode(payload)

      names = for {name, _node} <- children(nodes, root), do: name

      for command <- ~w(hotblock:hello hotblock:help hotblock:stats hotblock:fx
                        hotblock:watch hotblock:unwatch hotblock:spawn) do
        assert command in names, "#{command} is missing"
      end
    end

    test "has the fx subcommands, with a text where the command takes one" do
      {:ok, payload} = CommandTree.add_commands(@payload)
      {[root | _] = nodes, 0} = decode(payload)

      {_, fx} = List.keyfind(children(nodes, root), "hotblock:fx", 0)
      subcommands = Map.new(children(nodes, fx))

      assert Map.keys(subcommands) |> Enum.sort() ==
               ~w(actionbar bar sound title weather)

      assert [{"text", %{type: :greedy, executable: true}}] =
               children(nodes, subcommands["title"])

      assert children(nodes, subcommands["weather"]) |> Enum.map(&elem(&1, 0)) |> Enum.sort() ==
               ~w(clear rain thunder)
    end

    test "the bar takes a percent from 0 to 100, then a color, then a text" do
      {:ok, payload} = CommandTree.add_commands(@payload)
      {[root | _] = nodes, 0} = decode(payload)

      {_, fx} = List.keyfind(children(nodes, root), "hotblock:fx", 0)
      {_, bar} = List.keyfind(children(nodes, fx), "bar", 0)
      {_, percent} = List.keyfind(children(nodes, bar), "percent", 0)

      assert percent.type == {:integer, 0, 100}
      colors = Map.new(children(nodes, percent))
      assert Map.keys(colors) |> Enum.sort() == Hotblock.Commands.bar_colors()
      assert [{"text", %{type: :greedy, executable: true}}] = children(nodes, colors["red"])
    end

    test "spawn takes an entity, then an optional distance and direction" do
      {:ok, payload} = CommandTree.add_commands(@payload)
      {[root | _] = nodes, 0} = decode(payload)

      {_, spawn} = List.keyfind(children(nodes, root), "hotblock:spawn", 0)
      assert [{"entity", %{type: :word, executable: true} = entity}] = children(nodes, spawn)

      assert [{"distance", %{type: {:integer, 1, nil}, executable: true} = distance}] =
               children(nodes, entity)

      assert children(nodes, distance) |> Enum.map(&elem(&1, 0)) ==
               ~w(front behind left right)
    end

    test "commands without arguments can be run as they are" do
      {:ok, payload} = CommandTree.add_commands(@payload)
      {[root | _] = nodes, 0} = decode(payload)

      {_, hello} = List.keyfind(children(nodes, root), "hotblock:hello", 0)
      assert hello.executable
    end

    test "returns :error when the root is not the first node" do
      payload = binary_part(@payload, 0, byte_size(@payload) - 1) <> <<0x01>>

      assert CommandTree.add_commands(payload) == :error
    end

    test "returns :error for bytes that are not a command tree" do
      assert CommandTree.add_commands(<<0xFF, 0xFF>>) == :error
      assert CommandTree.add_commands(<<>>) == :error
    end
  end

  describe "add_to_frame/2" do
    test "changes declare_commands (0x10) in play" do
      {:ok, payload} = CommandTree.add_commands(@payload)

      assert CommandTree.add_to_frame(:play, <<0x10>> <> @payload) == <<0x10>> <> payload
    end

    test "leaves other packets and other phases as they are" do
      assert CommandTree.add_to_frame(:play, <<0x11>> <> @payload) == <<0x11>> <> @payload

      assert CommandTree.add_to_frame(:configuration, <<0x10>> <> @payload) ==
               <<0x10>> <> @payload
    end

    test "leaves a declare_commands it can't read as it is" do
      assert CommandTree.add_to_frame(:play, <<0x10, 0xFF, 0xFF>>) == <<0x10, 0xFF, 0xFF>>
    end
  end
end
