defmodule Hotblock.Protocol.NBTTest do
  use ExUnit.Case, async: true

  alias Hotblock.Protocol.NBT

  describe "encode_text/1" do
    test "encodes a compound with a single text string" do
      # compound, string tag named "text" with the value "Hi", end of compound
      assert NBT.encode_text("Hi") ==
               <<0x0A, 0x08, 0x00, 0x04, "text", 0x00, 0x02, "Hi", 0x00>>
    end

    test "encodes an empty text" do
      assert NBT.encode_text("") == <<0x0A, 0x08, 0x00, 0x04, "text", 0x00, 0x00, 0x00>>
    end

    test "uses the length in bytes, not in characters" do
      # "ñ" is 2 bytes in UTF-8
      assert NBT.encode_text("ñ") == <<0x0A, 0x08, 0x00, 0x04, "text", 0x00, 0x02, "ñ", 0x00>>
    end
  end
end
