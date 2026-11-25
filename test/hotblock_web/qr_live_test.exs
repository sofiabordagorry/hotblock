defmodule HotblockWeb.QrLiveTest do
  # async: false because the tests change the public URL
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint HotblockWeb.Endpoint

  setup do
    on_exit(fn -> Application.delete_env(:hotblock, :public_url) end)
    %{conn: build_conn()}
  end

  test "without the token it is a 404", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, "/admin/qr") end
    assert_error_sent 404, fn -> get(conn, "/admin/qr?token=nope") end
  end

  test "shows the QR and the public URL", %{conn: conn} do
    Application.put_env(:hotblock, :public_url, "https://hotblock.example.com")

    {:ok, _view, html} = live(conn, "/admin/qr?token=test-token")

    assert html =~ "<svg"
    assert html =~ "https://hotblock.example.com"
  end

  test "says how to set the public URL when there is none", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/admin/qr?token=test-token")

    refute html =~ "<svg"
    assert html =~ "HOTBLOCK_PUBLIC_URL"
  end
end
