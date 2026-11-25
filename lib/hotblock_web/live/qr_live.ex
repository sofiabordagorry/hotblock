defmodule HotblockWeb.QrLive do
  @moduledoc """
  A QR code of the panel's public URL, to project during a talk.
  """
  use Phoenix.LiveView

  @impl true
  def mount(params, _session, socket) do
    if not HotblockWeb.AdminToken.valid?(params["token"]), do: raise(HotblockWeb.NotFoundError)

    url = Application.get_env(:hotblock, :public_url)
    {:ok, assign(socket, url: url, qr: url && qr(url))}
  end

  defp qr(url), do: url |> EQRCode.encode() |> EQRCode.svg(width: 600)

  @impl true
  def render(assigns) do
    ~H"""
    <main class="qr-page">
      <div :if={@qr} class="qr">{Phoenix.HTML.raw(@qr)}</div>
      <p :if={@url} class="qr-url">{@url}</p>
      <p :if={!@url}>
        Start the proxy with <code>HOTBLOCK_PUBLIC_URL</code> set to the panel's public URL.
      </p>
    </main>
    """
  end
end
