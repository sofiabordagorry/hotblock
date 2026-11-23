defmodule HotblockWeb.NotFoundError do
  # Raised for a page that should look like it does not exist, like /admin
  # without the right token. Phoenix answers it with a 404.
  defexception message: "not found", plug_status: 404
end
