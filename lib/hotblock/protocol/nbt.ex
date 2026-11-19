defmodule Hotblock.Protocol.NBT do
  @moduledoc """
    Module for working with Named Binary Tags (NBT).
  """
  def encode_text(text) do
    <<0x0A>> <>
      <<0x08, 4::16, "text">> <>
      <<byte_size(text)::16>> <>
      text <>
      <<0x00>>
  end
end
