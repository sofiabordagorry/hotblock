defmodule HotblockWeb.EndpointTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  # Phoenix.ConnTest sends the requests straight to this endpoint, without
  # opening a port
  @endpoint HotblockWeb.Endpoint

  test "the home page answers with a page" do
    conn = get(build_conn(), "/")

    assert html_response(conn, 200) =~ "Hotblock"
  end

  test "PubSub is running and delivers messages" do
    Phoenix.PubSub.subscribe(Hotblock.PubSub, "endpoint_test")
    Phoenix.PubSub.broadcast(Hotblock.PubSub, "endpoint_test", :hello)

    assert_receive :hello
  end

  test "the endpoint and PubSub run in the same supervision tree as the proxy" do
    for name <- [HotblockWeb.Endpoint, Hotblock.PubSub, Hotblock.ConnectionSupervisor] do
      assert Hotblock.Supervisor in ancestors(name), "#{inspect(name)} is not under the app"
    end
  end

  # The supervisors above a process. PubSub starts its own supervisor, so it is
  # not a direct child of the app's supervisor, but it is still under it.
  defp ancestors(name) do
    {:dictionary, dictionary} = Process.info(Process.whereis(name), :dictionary)
    Keyword.get(dictionary, :"$ancestors", [])
  end
end
