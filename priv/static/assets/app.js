// Connects the page to its LiveView. Phoenix and LiveView come from
// /vendor as plain scripts, so they are globals here.
const Hooks = {}

// A tap on the map sends where it was, as an offset in blocks from the
// player. The map's SVG units are blocks, so the screen point only has to be
// turned into SVG coordinates.
Hooks.MapTap = {
  mounted() {
    this.el.addEventListener("click", (event) => {
      const svg = this.el
      if (!svg.getScreenCTM) return

      const point = svg.createSVGPoint()
      point.x = event.clientX
      point.y = event.clientY
      const { x, y } = point.matrixTransform(svg.getScreenCTM().inverse())

      const half = (value) => Math.round(value * 2) / 2
      this.pushEvent("spawn", { dx: half(x), dz: half(y) })
    })
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
})

liveSocket.connect()
