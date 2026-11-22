defmodule HotblockWeb.Endpoint do
  # Receives the HTTP requests and passes them to the router
  use Phoenix.Endpoint, otp_app: :hotblock

  plug HotblockWeb.Router
end
