defmodule Hotblock.RulesTest do
  use ExUnit.Case, async: true

  alias Hotblock.Effects.EntityWatch
  alias Hotblock.Protocol.Encoder.{Clientbound, Serverbound}
  alias Hotblock.Rules

  # The parts of the connection state the rules read and change: the player
  # at x 0, y 64, z 0, facing south, with no boss bar and nothing watched
  @state %{
    position: {0.0, 64.0, 0.0},
    yaw: 0.0,
    boss_bar: nil,
    entity_watch: EntityWatch.new()
  }

  describe "handle_command/2" do
    test "/hotblock:hello replies in the chat" do
      assert Rules.handle_command("hotblock:hello", @state) ==
               {:ok, [{:client, Clientbound.system_chat("Hello from Elixir!")}], @state}
    end

    test "/hotblock:fx title sends the times, the subtitle and the title" do
      title =
        Clientbound.set_title_time(10, 70, 20) <>
          Clientbound.set_title_subtitle("there") <>
          Clientbound.set_title_text("Hi")

      assert Rules.handle_command("hotblock:fx title Hi | there", @state) ==
               {:ok, [{:client, title}], @state}
    end

    test "/hotblock:fx title without a subtitle sends an empty one" do
      title =
        Clientbound.set_title_time(10, 70, 20) <>
          Clientbound.set_title_subtitle("") <>
          Clientbound.set_title_text("Hi")

      assert Rules.handle_command("hotblock:fx title Hi", @state) ==
               {:ok, [{:client, title}], @state}
    end

    test "/hotblock:fx actionbar shows the text above the hotbar" do
      assert Rules.handle_command("hotblock:fx actionbar Hi", @state) ==
               {:ok, [{:client, Clientbound.action_bar("Hi")}], @state}
    end

    test "/hotblock:fx weather changes the weather" do
      assert Rules.handle_command("hotblock:fx weather rain", @state) ==
               {:ok, [{:client, Clientbound.weather(:rain)}], @state}
    end

    test "/hotblock:fx bar adds a bar and keeps it in the state" do
      bar = %{title: "Hi", health: 0.5, color: :red}

      assert Rules.handle_command("hotblock:fx bar 50 red Hi", @state) ==
               {:ok, [{:client, Clientbound.boss_bar_add("Hi", 0.5, :red)}],
                %{@state | boss_bar: bar}}
    end

    test "/hotblock:fx bar off removes the bar from the state" do
      state = %{@state | boss_bar: %{title: "Hi", health: 0.5, color: :red}}

      assert Rules.handle_command("hotblock:fx bar off", state) ==
               {:ok, [{:client, Clientbound.boss_bar_remove()}], @state}
    end

    test "/hotblock:fx sound plays the sound at the player position" do
      sound = Clientbound.sound_effect("minecraft:entity.player.levelup", {0.0, 64.0, 0.0})

      assert Rules.handle_command("hotblock:fx sound entity.player.levelup", @state) ==
               {:ok, [{:client, sound}], @state}
    end

    test "/hotblock:watch and /hotblock:unwatch reply and change the entity watch" do
      assert {:ok, [{:client, reply}], state} =
               Rules.handle_command("hotblock:watch zombie 10", @state)

      assert reply == Clientbound.system_chat("Watching zombie within 10 blocks")
      assert state.entity_watch.watches == %{"zombie" => 10}

      assert {:ok, [{:client, reply}], state} =
               Rules.handle_command("hotblock:unwatch zombie", state)

      assert reply == Clientbound.system_chat("Stopped watching zombie")
      assert state.entity_watch.watches == %{}
    end

    test "/hotblock:spawn sends the summon command to the server" do
      summon = Serverbound.chat_command("summon minecraft:zombie 0.00 64.00 3.00")

      assert Rules.handle_command("hotblock:spawn zombie", @state) ==
               {:ok, [{:server, summon}], @state}
    end

    test "/hotblock:spawn replies in the chat for an unknown entity" do
      assert Rules.handle_command("hotblock:spawn dragon", @state) ==
               {:ok, [{:client, Clientbound.system_chat("Unknown entity: dragon")}], @state}
    end

    test "/hotblock:help lists the commands" do
      help = Clientbound.system_chat(Hotblock.Commands.help_text())

      assert Rules.handle_command("hotblock:help", @state) == {:ok, [{:client, help}], @state}
    end

    test "/hotblock:stats shows how many packets went each way" do
      state = Map.put(@state, :stats, %{from_client: 12, from_server: 345})
      stats = Clientbound.system_chat("Packets: 12 from you, 345 from the server")

      assert Rules.handle_command("hotblock:stats", state) == {:ok, [{:client, stats}], state}
    end

    test "returns :forward for commands that are not the proxy's or are not valid" do
      for command <- [
            "help",
            "hotblock:unknown",
            "hotblock:fx title",
            "hotblock:fx weather snow",
            "hotblock:fx bar 500 red Hi",
            "hotblock:watch zombie 0",
            "hotblock:spawn zombie 0"
          ] do
        assert Rules.handle_command(command, @state) == :forward, "for #{command}"
      end
    end
  end

  describe "handle_effect/3" do
    test ":title shows the text as a title, like /hotblock:fx title" do
      assert Rules.handle_effect(:title, "Hi", @state) ==
               Rules.handle_command("hotblock:fx title Hi", @state)
    end

    test ":actionbar, :weather and :sound do what their commands do" do
      for {effect, arg, command} <- [
            {:actionbar, "Hi", "hotblock:fx actionbar Hi"},
            {:weather, :rain, "hotblock:fx weather rain"},
            {:sound, "entity.player.levelup", "hotblock:fx sound entity.player.levelup"}
          ] do
        assert Rules.handle_effect(effect, arg, @state) == Rules.handle_command(command, @state),
               "for #{effect}"
      end
    end

    test ":bar shows the boss bar, like /hotblock:fx bar" do
      bar = %{health: 0.5, color: :red, title: "Hi"}

      assert Rules.handle_effect(:bar, bar, @state) ==
               Rules.handle_command("hotblock:fx bar 50 red Hi", @state)
    end

    test ":bar :off removes the boss bar, like /hotblock:fx bar off" do
      state = %{@state | boss_bar: %{health: 0.5, color: :red, title: "Hi"}}

      assert Rules.handle_effect(:bar, :off, state) ==
               Rules.handle_command("hotblock:fx bar off", state)
    end

    test ":watch and :unwatch do what their commands do" do
      assert Rules.handle_effect(:watch, {"zombie", 10}, @state) ==
               Rules.handle_command("hotblock:watch zombie 10", @state)

      {:ok, _, watching} = Rules.handle_command("hotblock:watch zombie 10", @state)

      assert Rules.handle_effect(:unwatch, "zombie", watching) ==
               Rules.handle_command("hotblock:unwatch zombie", watching)
    end

    test ":spawn summons the entity at the player's position plus the offset" do
      assert Rules.handle_effect(:spawn, {"zombie", {2.0, -3.0}}, @state) ==
               {:ok,
                [{:server, Serverbound.chat_command("summon minecraft:zombie 2.00 64.00 -3.00")}],
                @state}
    end

    test ":spawn replies in the chat when the position is not known or the entity is unknown" do
      not_known =
        Clientbound.system_chat("Your position is not known yet, move a bit and try again")

      assert Rules.handle_effect(:spawn, {"zombie", {2.0, -3.0}}, %{@state | position: nil}) ==
               {:ok, [{:client, not_known}], %{@state | position: nil}}

      assert Rules.handle_effect(:spawn, {"dragon_cat", {2.0, -3.0}}, @state) ==
               {:ok, [{:client, Clientbound.system_chat("Unknown entity: dragon_cat")}], @state}
    end

    @tag :capture_log
    test "ignores an unknown effect" do
      assert Rules.handle_effect(:unknown, "hi", @state) == {:ok, [], @state}
    end
  end
end
