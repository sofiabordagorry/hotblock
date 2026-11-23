defmodule HotblockWeb.Endpoint do
  # Receives the HTTP requests and passes them to the router
  use Phoenix.Endpoint, otp_app: :hotblock

  # The session lives in a signed cookie
  @session_options [
    store: :cookie,
    key: "_hotblock_key",
    signing_salt: "91GYrAU3",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]
  plug Plug.Static, at: "/", from: :hotblock, only: ~w(assets)

  plug Plug.Static, at: "/vendor", from: {:phoenix, "priv/static"}, only: ~w(phoenix.min.js)

  plug Plug.Static,
    at: "/vendor",
    from: {:phoenix_live_view, "priv/static"},
    only: ~w(phoenix_live_view.min.js)

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.Session, @session_options
  plug HotblockWeb.Router
end
