defmodule HotblockWeb.AdminToken do
  # The token of the admin pages, from HOTBLOCK_ADMIN_TOKEN. Without one, no
  # token is valid.
  def valid?(token) when is_binary(token) do
    expected = Application.get_env(:hotblock, :admin_token)
    is_binary(expected) and expected != "" and Plug.Crypto.secure_compare(token, expected)
  end

  def valid?(_token), do: false
end
