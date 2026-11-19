import Config

# Tests use a different port so they can run while the real server is up
config :hotblock, server_port: 25576

config :hotblock, packet_logger_enabled: false
