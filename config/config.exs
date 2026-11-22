import Config

# Port of the real Minecraft server the proxy forwards to
config :hotblock, server_port: 25566

# The web panel, served by Phoenix next to the proxy
config :hotblock, HotblockWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  pubsub_server: Hotblock.PubSub,
  live_view: [signing_salt: "hotblock"]

# Elixir's built-in JSON, so there is no need for Jason
config :phoenix, :json_library, JSON

import_config "#{config_env()}.exs"
