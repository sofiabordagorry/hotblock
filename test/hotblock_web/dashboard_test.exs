defmodule HotblockWeb.DashboardTest do
  # async: false because one test changes the admin token
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  @endpoint HotblockWeb.Endpoint

  # The dashboard uses the admin token as the password of a browser login
  defp login(conn, password) do
    Plug.Conn.put_req_header(
      conn,
      "authorization",
      Plug.BasicAuth.encode_basic_auth("admin", password)
    )
  end

  test "/dashboard asks for the admin login" do
    conn = get(build_conn(), "/dashboard/home")

    assert conn.status == 401
  end

  test "/dashboard with a wrong password is refused" do
    conn = build_conn() |> login("nope") |> get("/dashboard/home")

    assert conn.status == 401
  end

  test "/dashboard opens with the admin token as the password" do
    conn = build_conn() |> login("test-token") |> get("/dashboard/home")

    assert html_response(conn, 200) =~ "Dashboard"
  end

  test "without an admin token configured, /dashboard is a 404" do
    Application.put_env(:hotblock, :admin_token, nil)

    assert_error_sent 404, fn -> build_conn() |> login("") |> get("/dashboard/home") end
  after
    Application.put_env(:hotblock, :admin_token, "test-token")
  end

  test "the metrics page shows the proxy's metrics" do
    names = Enum.map(HotblockWeb.Telemetry.metrics(), &Enum.join(&1.name, "."))

    for name <- ~w(hotblock.connections.count hotblock.packets.from_client
                   hotblock.packets.from_server hotblock.reload.stop.duration) do
      assert name in names, "#{name} is missing"
    end
  end
end
