defmodule Hotblock.Commands do
  # The proxy's own commands
  @commands [
    %{usage: "/hotblock:hello", description: "Says hello from the proxy"},
    %{
      usage: "/hotblock:fx title <title> [| <subtitle>]",
      description: "Shows a title on the screen"
    },
    %{usage: "/hotblock:fx actionbar <text>", description: "Shows a text above the hotbar"},
    %{
      usage: "/hotblock:fx weather clear|rain|thunder",
      description: "Changes the weather only for you"
    },
    %{usage: "/hotblock:help", description: "Lists the proxy's commands"}
  ]

  def all, do: @commands

  def help_text do
    lines = Enum.map(@commands, fn command -> "#{command.usage} - #{command.description}" end)
    Enum.join(["Hotblock commands:" | lines], "\n")
  end
end
