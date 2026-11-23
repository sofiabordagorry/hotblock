defmodule HotblockWeb.Router do
  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HotblockWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", HotblockWeb do
    pipe_through :browser

    live "/", PanelLive, :index
    live "/admin", PanelLive, :admin
  end
end
