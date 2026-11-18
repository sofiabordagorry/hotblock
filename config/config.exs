import Config

# Port of the real Minecraft server the proxy forwards to
config :hotblock, server_port: 25566

import_config "#{config_env()}.exs"
