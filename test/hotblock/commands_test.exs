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
               /hotblock:help - Lists the proxy's commands\
               """
    end

    test "has a line for every command in the list" do
      lines = String.split(Commands.help_text(), "\n")

      assert length(lines) == length(Commands.all()) + 1
    end
  end
end
