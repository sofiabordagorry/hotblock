import Config

# Log every packet (state, direction, ID, size)
config :hotblock, packet_logger_enabled: false

# The token for /admin?token=..., which has the kick and crash buttons.
# There is no default: without HOTBLOCK_ADMIN_TOKEN, /admin is always a 404.
config :hotblock, admin_token: System.get_env("HOTBLOCK_ADMIN_TOKEN")

# The panel's public URL, shown as a QR code at /admin/qr
config :hotblock, public_url: System.get_env("HOTBLOCK_PUBLIC_URL")

# Serve the web panel on port 4000 when running iex -S mix
config :hotblock, HotblockWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  server: true,
  secret_key_base: "7XxroUxicDS4t4J5QYNgFNqKJZ9AyfEtjgWL5aISRlGMmHaobRRNWo1PC11dF6ih"
