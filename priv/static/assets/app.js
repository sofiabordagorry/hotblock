// Connects the page to its LiveView. Phoenix and LiveView come from
// /vendor as plain scripts, so they are globals here.
const Hooks = {}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
})

liveSocket.connect()
