defmodule Hotblock.Protocol.TypesTest do
  use ExUnit.Case, async: true

  alias Hotblock.Protocol.Types

  describe "decode_varint/1" do
    # Sample values from the "Java Edition protocol" page on minecraft.wiki
    @samples [
      {0, <<0x00>>},
      {1, <<0x01>>},
      {2, <<0x02>>},
      {127, <<0x7F>>},
      {128, <<0x80, 0x01>>},
      {255, <<0xFF, 0x01>>},
      {25565, <<0xDD, 0xC7, 0x01>>},
      {2_097_151, <<0xFF, 0xFF, 0x7F>>},
      {2_147_483_647, <<0xFF, 0xFF, 0xFF, 0xFF, 0x07>>},
      {-1, <<0xFF, 0xFF, 0xFF, 0xFF, 0x0F>>},
      {-2_147_483_648, <<0x80, 0x80, 0x80, 0x80, 0x08>>}
    ]

    for {value, bytes} <- @samples do
      test "decodes #{inspect(bytes, base: :hex)} as #{value}" do
        assert Types.decode_varint(unquote(bytes)) == {:ok, unquote(value), ""}
      end
    end

    test "returns the bytes after the varint as rest" do
      assert Types.decode_varint(<<0x01, 0xAA, 0xBB>>) == {:ok, 1, <<0xAA, 0xBB>>}
      assert Types.decode_varint(<<0x80, 0x01, 0xAA>>) == {:ok, 128, <<0xAA>>}
    end

    test "keeps only the low 32 bits when the 5th byte overflows" do
      assert Types.decode_varint(<<0xFF, 0xFF, 0xFF, 0xFF, 0x7F>>) == {:ok, -1, ""}
    end

    test "returns :incomplete for an empty binary" do
      assert Types.decode_varint(<<>>) == :incomplete
    end

    test "returns :incomplete when the last byte has the continuation bit set" do
      assert Types.decode_varint(<<0x80>>) == :incomplete
      assert Types.decode_varint(<<0xFF, 0xFF>>) == :incomplete
      assert Types.decode_varint(<<0xFF, 0xFF, 0xFF, 0xFF>>) == :incomplete
    end

    test "returns an error when the varint is longer than 5 bytes" do
      assert Types.decode_varint(<<0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>) ==
               {:error, :varint_too_long}

      assert Types.decode_varint(<<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01>>) ==
               {:error, :varint_too_long}
    end
  end

  describe "encode_varint/1" do
    for {value, bytes} <- @samples, value >= 0 do
      test "encodes #{value} as #{inspect(bytes, base: :hex)}" do
        assert Types.encode_varint(unquote(value)) == unquote(bytes)
      end
    end

    test "gives back the same value when decoded" do
      for value <- [0, 1, 127, 128, 300, 25565, 2_097_151, 2_147_483_647] do
        assert Types.decode_varint(Types.encode_varint(value)) == {:ok, value, ""}
      end
    end
  end

  describe "decode_string/1" do
    test "decodes the string and returns the bytes after it" do
      assert Types.decode_string(<<0x05, "hello", 0xAA>>) == {:ok, "hello", <<0xAA>>}
    end

    test "decodes an empty string" do
      assert Types.decode_string(<<0x00>>) == {:ok, "", ""}
    end

    test "returns an error when the string is cut" do
      assert Types.decode_string(<<0x05, "hel">>) == {:error, :invalid_string}
    end
  end
end
