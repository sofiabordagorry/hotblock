defmodule Hotblock.CommandTree do
  @moduledoc """
  Adds the proxy's commands to the server's declare_commands, so the client
  autocompletes them. Only the root (node 0) is read; the rest is copied as is.
  """
  import Bitwise

  alias Hotblock.Commands
  alias Hotblock.Packets.Clientbound
  alias Hotblock.Protocol.Types

  @root 0x00
  @literal 0x01
  @argument 0x02
  @executable 0x04
  @redirect 0x08

  def add_to_frame(:play, frame) do
    declare_commands = Clientbound.declare_commands()

    with {:ok, ^declare_commands, payload} <- Types.decode_varint(frame),
         {:ok, payload} <- add_commands(payload) do
      Types.encode_varint(declare_commands) <> payload
    else
      _ -> frame
    end
  end

  def add_to_frame(_phase, frame), do: frame

  def add_commands(payload) do
    with {:ok, count, nodes} when count > 0 <- Types.decode_varint(payload),
         {:ok, root_children, other_nodes} <- decode_root(nodes),
         {other_nodes, <<0>>} <- split_root_index(other_nodes) do
      {new_nodes, new_children} = encode_commands(commands(), count)
      root = encode_node(@root, root_children ++ new_children, <<>>)

      {:ok,
       Types.encode_varint(count + length(new_nodes)) <>
         root <> other_nodes <> IO.iodata_to_binary(new_nodes) <> <<0>>}
    else
      _ -> :error
    end
  end

  defp decode_root(<<flags, rest::binary>>) when (flags &&& 0x03) == @root do
    with {:ok, count, rest} <- Types.decode_varint(rest),
         {:ok, children, rest} <- decode_varints(rest, count, []),
         {:ok, rest} <- skip_redirect(flags, rest) do
      {:ok, children, rest}
    end
  end

  defp decode_root(_nodes), do: :error

  defp decode_varints(rest, 0, acc), do: {:ok, Enum.reverse(acc), rest}

  defp decode_varints(rest, count, acc) do
    case Types.decode_varint(rest) do
      {:ok, value, rest} -> decode_varints(rest, count - 1, [value | acc])
      _ -> :error
    end
  end

  defp skip_redirect(flags, rest) when (flags &&& @redirect) != 0 do
    case Types.decode_varint(rest) do
      {:ok, _node, rest} -> {:ok, rest}
      _ -> :error
    end
  end

  defp skip_redirect(_flags, rest), do: {:ok, rest}

  # The root's index, 0, is the last byte
  defp split_root_index(rest) when byte_size(rest) > 0 do
    {binary_part(rest, 0, byte_size(rest) - 1), binary_part(rest, byte_size(rest) - 1, 1)}
  end

  defp split_root_index(_rest), do: :error

  defp commands do
    colors = for color <- Commands.bar_colors(), do: literal(color, [text("text")])
    directions = for direction <- ~w(front behind left right), do: run(direction)

    [
      run("hotblock:hello"),
      run("hotblock:help"),
      run("hotblock:stats"),
      literal("hotblock:fx", [
        literal("title", [text("text")]),
        literal("actionbar", [text("text")]),
        literal("weather", [run("clear"), run("rain"), run("thunder")]),
        literal("bar", [run("off"), {:integer, "percent", false, {0, 100}, colors}]),
        literal("sound", [word("sound")])
      ]),
      literal("hotblock:watch", [word("entity", [{:integer, "radius", true, {1, nil}, []}])]),
      literal("hotblock:unwatch", [word("entity")]),
      literal("hotblock:spawn", [
        word("entity", [{:integer, "distance", true, {1, nil}, directions}])
      ])
    ]
  end

  defp run(name), do: {:literal, name, true, []}
  defp literal(name, children), do: {:literal, name, false, children}
  defp word(name, children \\ []), do: {:word, name, true, children}
  defp text(name), do: {:text, name, true, []}

  # Returns the encoded nodes and the indices of the top-level ones
  defp encode_commands(commands, first) do
    {nodes, indices, _next} = encode_level(commands, first)
    {nodes, indices}
  end

  defp encode_level(nodes, next) do
    indices = Enum.to_list(next..(next + length(nodes) - 1)//1)
    next = next + length(nodes)

    {children_encoded, child_indices, next} =
      Enum.reduce(nodes, {[], [], next}, fn node, {encoded, indices, next} ->
        {child_nodes, child_ids, next} = encode_level(children(node), next)
        {encoded ++ child_nodes, indices ++ [child_ids], next}
      end)

    level = Enum.zip_with(nodes, child_indices, &encode(&1, &2))
    {level ++ children_encoded, indices, next}
  end

  defp children({_kind, _name, _run, children}), do: children
  defp children({:integer, _name, _run, _range, children}), do: children

  defp encode({:literal, name, run, _}, children) do
    encode_node(@literal ||| executable(run), children, Types.encode_string(name))
  end

  # brigadier:string (5): 0 is one word, 2 is the rest of the line
  defp encode({:word, name, run, _}, children) do
    encode_node(@argument ||| executable(run), children, Types.encode_string(name) <> <<5, 0>>)
  end

  defp encode({:text, name, run, _}, children) do
    encode_node(@argument ||| executable(run), children, Types.encode_string(name) <> <<5, 2>>)
  end

  # brigadier:integer (3)
  defp encode({:integer, name, run, {min, max}, _}, children) do
    flags = if(min, do: 0x01, else: 0) ||| if(max, do: 0x02, else: 0)

    bounds =
      if(min, do: <<min::signed-32>>, else: <<>>) <> if(max, do: <<max::signed-32>>, else: <<>>)

    encode_node(
      @argument ||| executable(run),
      children,
      Types.encode_string(name) <> <<3, flags>> <> bounds
    )
  end

  defp executable(true), do: @executable
  defp executable(false), do: 0

  defp encode_node(flags, children, data) do
    <<flags>> <>
      Types.encode_varint(length(children)) <>
      Enum.map_join(children, &Types.encode_varint/1) <> data
  end
end
