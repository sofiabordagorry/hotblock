defmodule Hotblock.BossBarTest do
  use ExUnit.Case, async: true

  alias Hotblock.BossBar
  alias Hotblock.Protocol.Encoder

  @bar %{title: "Hi", health: 0.5, color: :red}

  describe "packets/2" do
    test "adds the bar when there was none" do
      assert BossBar.packets(nil, @bar) == Encoder.boss_bar_add("Hi", 0.5, :red)
    end

    test "removes the bar when it is turned off" do
      assert BossBar.packets(@bar, nil) == Encoder.boss_bar_remove()
    end

    test "sends nothing when there was no bar and it is turned off" do
      assert BossBar.packets(nil, nil) == <<>>
    end

    test "sends nothing when the bar does not change" do
      assert BossBar.packets(@bar, @bar) == <<>>
    end

    test "only updates the health when only the health changes" do
      assert BossBar.packets(@bar, %{@bar | health: 0.8}) == Encoder.boss_bar_update_health(0.8)
    end

    test "only updates the title when only the title changes" do
      assert BossBar.packets(@bar, %{@bar | title: "Bye"}) == Encoder.boss_bar_update_title("Bye")
    end

    test "only updates the style when only the color changes" do
      assert BossBar.packets(@bar, %{@bar | color: :blue}) == Encoder.boss_bar_update_style(:blue)
    end

    test "updates health, title and style, in that order, when everything changes" do
      new_bar = %{title: "Bye", health: 0.8, color: :blue}

      assert BossBar.packets(@bar, new_bar) ==
               Encoder.boss_bar_update_health(0.8) <>
                 Encoder.boss_bar_update_title("Bye") <>
                 Encoder.boss_bar_update_style(:blue)
    end
  end
end
