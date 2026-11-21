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
    %{
      usage: "/hotblock:watch <entity> [radius]",
      description: "Warns you when that entity gets close"
    },
    %{usage: "/hotblock:unwatch <entity>", description: "Stops warning about that entity"},
    %{
      usage: "/hotblock:spawn <entity> [distance] [front|behind|left|right]",
      description: "Spawns an entity next to you, in front by default"
    },
    %{usage: "/hotblock:help", description: "Lists the proxy's commands"}
  ]

  # Radius for /hotblock:watch when none is given, in blocks
  @default_watch_radius 16

  # Distance and direction for /hotblock:spawn when they are not given
  @default_spawn_distance 3
  @default_spawn_direction :front

  @directions %{
    "front" => :front,
    "right" => :right,
    "behind" => :behind,
    "left" => :left
  }

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

  # Parses "<entity> [radius]". The radius is a whole number above 0, and
  # @default_watch_radius when it is missing.
  def parse_watch(args) do
    case String.split(args, " ") do
      [name] when name != "" ->
        {:ok, name, @default_watch_radius}

      [name, radius] when name != "" ->
        case Integer.parse(radius) do
          {radius, ""} when radius > 0 -> {:ok, name, radius}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  # Parses "<entity> [distance] [direction]". The distance is a whole number
  # above 0. The second word can be the distance or the direction.
  def parse_spawn(args) do
    case String.split(args, " ") do
      [name] when name != "" ->
        {:ok, name, @default_spawn_distance, @default_spawn_direction}

      [name, word] when name != "" ->
        case Map.fetch(@directions, word) do
          {:ok, direction} ->
            {:ok, name, @default_spawn_distance, direction}

          :error ->
            with {:ok, distance} <- parse_distance(word) do
              {:ok, name, distance, @default_spawn_direction}
            end
        end

      [name, distance, direction] when name != "" ->
        with {:ok, distance} <- parse_distance(distance),
             {:ok, direction} <- Map.fetch(@directions, direction) do
          {:ok, name, distance, direction}
        end

      _ ->
        :error
    end
  end

  defp parse_distance(text) do
    case Integer.parse(text) do
      {distance, ""} when distance > 0 -> {:ok, distance}
      _ -> :error
    end
  end
end
