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
    %{usage: "/hotblock:fx bar <percent> <color> <text>", description: "Shows a boss bar"},
    %{usage: "/hotblock:fx bar off", description: "Removes the boss bar"},
    %{usage: "/hotblock:fx sound <sound>", description: "Plays a sound where you stand"},
    %{usage: "/hotblock:help", description: "Lists the proxy's commands"}
  ]

  @bar_colors %{
    "pink" => :pink,
    "blue" => :blue,
    "red" => :red,
    "green" => :green,
    "yellow" => :yellow,
    "purple" => :purple,
    "white" => :white
  }

  def all, do: @commands

  def help_text do
    lines = Enum.map(@commands, fn command -> "#{command.usage} - #{command.description}" end)
    Enum.join(["Hotblock commands:" | lines], "\n")
  end

  # Parses "<percent> <color> <text>". The percent is a whole number from 0 to
  # 100 and is returned as the health, from 0.0 to 1.0.
  def parse_bar(args) do
    with [percent, color, text] when text != "" <- String.split(args, " ", parts: 3),
         {percent, ""} when percent in 0..100 <- Integer.parse(percent),
         {:ok, color} <- Map.fetch(@bar_colors, color) do
      {:ok, percent / 100, color, text}
    else
      _ -> :error
    end
  end
end
