import Config

# Log every packet (state, direction, ID, size)
config :hotblock, packet_logger_enabled: false

# Serve the web panel on port 4000 when running iex -S mix
config :hotblock, HotblockWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  server: true,
  secret_key_base: "7XxroUxicDS4t4J5QYNgFNqKJZ9AyfEtjgWL5aISRlGMmHaobRRNWo1PC11dF6ih"
