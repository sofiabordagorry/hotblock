defmodule HotblockWeb.Router do
  use Phoenix.Router

  import Phoenix.LiveView.Router
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HotblockWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :admin do
    plug :require_admin
  end

  # The dashboard asks for a browser login: user "admin", and the admin token
  # as the password. Without a token configured, it does not exist.
  scope "/" do
    pipe_through [:browser, :admin]

    live_dashboard "/dashboard", metrics: HotblockWeb.Telemetry
  end

  scope "/", HotblockWeb do
    pipe_through :browser

    live "/", PanelLive, :index
    live "/admin", PanelLive, :admin
    live "/admin/qr", QrLive
  end

  defp require_admin(conn, _opts) do
    case Application.get_env(:hotblock, :admin_token) do
      token when is_binary(token) and token != "" ->
        Plug.BasicAuth.basic_auth(conn, username: "admin", password: token)

      _ ->
        raise HotblockWeb.NotFoundError
    end
  end
end
