defmodule Hotblock.Effects.BossBar do
  # The boss bar the proxy shows to a player. A bar is nil when there is none,
  # or %{title: ..., health: ..., color: ...}.
  alias Hotblock.Protocol.Encoder

  # Returns the packets that take the client from the old bar to the new one.
  # A bar that already exists is updated, so the client never shows two.
  def packets(nil, nil), do: <<>>
  def packets(nil, new), do: Encoder.boss_bar_add(new.title, new.health, new.color)
  def packets(_old, nil), do: Encoder.boss_bar_remove()

  def packets(old, new) do
    health =
      if old.health != new.health, do: Encoder.boss_bar_update_health(new.health), else: <<>>

    title = if old.title != new.title, do: Encoder.boss_bar_update_title(new.title), else: <<>>
    style = if old.color != new.color, do: Encoder.boss_bar_update_style(new.color), else: <<>>

    health <> title <> style
  end
end
