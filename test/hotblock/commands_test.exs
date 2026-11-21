defmodule Hotblock.CommandsTest do
  use ExUnit.Case, async: true

  alias Hotblock.Commands

  describe "all/0" do
    test "has a usage and a description for every command" do
      for command <- Commands.all() do
        assert "/" <> _ = command.usage
        assert command.description != ""
      end
    end

    test "includes every command the proxy handles" do
      usages = Enum.map(Commands.all(), & &1.usage)

      assert "/hotblock:hello" in usages
      assert "/hotblock:fx title <title> [| <subtitle>]" in usages
      assert "/hotblock:fx actionbar <text>" in usages
      assert "/hotblock:fx weather clear|rain|thunder" in usages
      assert "/hotblock:fx bar <percent> <color> <text>" in usages
      assert "/hotblock:fx bar off" in usages
      assert "/hotblock:fx sound <sound>" in usages
      assert "/hotblock:help" in usages
    end
  end

  describe "help_text/0" do
    test "has a header and one line per command" do
      assert Commands.help_text() ==
               """
               Hotblock commands:
               /hotblock:hello - Says hello from the proxy
               /hotblock:fx title <title> [| <subtitle>] - Shows a title on the screen
               /hotblock:fx actionbar <text> - Shows a text above the hotbar
               /hotblock:fx weather clear|rain|thunder - Changes the weather only for you
               /hotblock:fx bar <percent> <color> <text> - Shows a boss bar
               /hotblock:fx bar off - Removes the boss bar
               /hotblock:fx sound <sound> - Plays a sound where you stand
               /hotblock:help - Lists the proxy's commands\
               """
    end

    test "has a line for every command in the list" do
      lines = String.split(Commands.help_text(), "\n")

      assert length(lines) == length(Commands.all()) + 1
    end
  end

  describe "parse_bar/1" do
    test "returns the health from 0 to 1, the color and the text" do
      assert Commands.parse_bar("50 red Hello") == {:ok, 0.5, :red, "Hello"}
      assert Commands.parse_bar("0 blue Hello") == {:ok, 0.0, :blue, "Hello"}
      assert Commands.parse_bar("100 white Hello") == {:ok, 1.0, :white, "Hello"}
    end

    test "keeps the spaces in the text" do
      assert Commands.parse_bar("50 green Hello world") == {:ok, 0.5, :green, "Hello world"}
    end

    test "accepts every boss bar color" do
      for color <- ~w(pink blue red green yellow purple white) do
        assert {:ok, _, atom, _} = Commands.parse_bar("50 #{color} Hi")
        assert Atom.to_string(atom) == color
      end
    end

    test "returns :error when the percent is not a whole number from 0 to 100" do
      assert Commands.parse_bar("101 red Hi") == :error
      assert Commands.parse_bar("-1 red Hi") == :error
      assert Commands.parse_bar("50.5 red Hi") == :error
      assert Commands.parse_bar("half red Hi") == :error
    end

    test "returns :error for an unknown color" do
      assert Commands.parse_bar("50 orange Hi") == :error
    end

    test "returns :error when the text is missing" do
      assert Commands.parse_bar("50 red") == :error
      assert Commands.parse_bar("50 red ") == :error
      assert Commands.parse_bar("50") == :error
      assert Commands.parse_bar("") == :error
    end
  end
end
