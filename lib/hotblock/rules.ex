defmodule Hotblock.Rules do
  @moduledoc """
  What each of the proxy's commands does, it returns what to send and to whom (client or server)
  """

  alias Hotblock.Commands
  alias Hotblock.Effects.{BossBar, EntityWatch, Sound, Spawn}
  alias Hotblock.Protocol.Encoder.Clientbound

  def handle_command("hotblock:hello", state) do
    {:ok, [{:client, Clientbound.system_chat("Hello from Elixir!")}], state}
  end

  def handle_command("hotblock:fx title " <> text, state) when text != "" do
    {title, subtitle} = get_title(text)

    {:ok,
     [
       {:client,
        Clientbound.set_title_time(10, 70, 20) <>
          Clientbound.set_title_subtitle(subtitle) <> Clientbound.set_title_text(title)}
     ], state}
  end

  def handle_command("hotblock:fx actionbar " <> text, state) when text != "" do
    {:ok, [{:client, Clientbound.action_bar(text)}], state}
  end

  def handle_command("hotblock:fx weather " <> weather, state)
      when weather in ["clear", "rain", "thunder"] do
    {:ok, [{:client, Clientbound.weather(String.to_existing_atom(weather))}], state}
  end

  def handle_command("hotblock:fx bar off", state) do
    {:ok, [{:client, BossBar.packets(state.boss_bar, nil)}], %{state | boss_bar: nil}}
  end

  def handle_command("hotblock:fx bar " <> args, state) do
    case Commands.parse_bar(args) do
      {:ok, health, color, text} ->
        bar = %{title: text, health: health, color: color}
        {:ok, [{:client, BossBar.packets(state.boss_bar, bar)}], %{state | boss_bar: bar}}

      :error ->
        :forward
    end
  end

  def handle_command("hotblock:watch " <> args, state) do
    case Commands.parse_watch(args) do
      {:ok, name, radius} ->
        {reply, entity_watch} = EntityWatch.watch(state.entity_watch, name, radius)
        {:ok, [{:client, reply}], %{state | entity_watch: entity_watch}}

      :error ->
        :forward
    end
  end

  def handle_command("hotblock:unwatch " <> name, state) when name != "" do
    {reply, entity_watch} = EntityWatch.unwatch(state.entity_watch, name)
    {:ok, [{:client, reply}], %{state | entity_watch: entity_watch}}
  end

  def handle_command("hotblock:help", state) do
    {:ok, [{:client, Clientbound.system_chat(Commands.help_text())}], state}
  end

  def handle_command("hotblock:fx sound " <> name, state) do
    {:ok, [{:client, Sound.packets(name, state.position)}], state}
  end

  def handle_command("hotblock:spawn " <> args, state) do
    case Commands.parse_spawn(args) do
      {:ok, name, distance, direction} ->
        case Spawn.packets(name, distance, direction, state.position, state.yaw) do
          {:client, packet} ->
            {:ok, [{:client, packet}], state}

          {:server, packet} ->
            {:ok, [{:server, packet}], state}
        end

      :error ->
        :forward
    end
  end

  def handle_command("hotblock:stats", state) do
    %{from_client: from_client, from_server: from_server} = state.stats
    text = "Packets: #{from_client} from you, #{from_server} from the server"
    {:ok, [{:client, Clientbound.system_chat(text)}], state}
  end

  def handle_command(_command, _state), do: :forward

  # The text is "<title>" or "<title> | <subtitle>"
  defp get_title(text) do
    case String.split(text, " | ", parts: 2) do
      [title, subtitle] -> {title, subtitle}
      [title] -> {title, ""}
    end
  end
end
