defmodule Hotblock.Protocol.Encoder.ServerboundTest do
  use ExUnit.Case, async: true

  alias Hotblock.Protocol.Encoder.Serverbound

  describe "chat_command/1" do
    test "builds the serverbound frame with the command as a string" do
      assert Serverbound.chat_command("time set day") == <<0x0E, 0x07, 0x0C, "time set day">>
    end
  end
end
