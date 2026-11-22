defmodule HotblockWeb.PageController do
  use Phoenix.Controller, formats: [:html]

  def home(conn, _params) do
    html(conn, "<h1>Hotblock</h1><p>The proxy is running.</p>")
  end
end
