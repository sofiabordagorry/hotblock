import Config

# Log every packet (state, direction, ID, size)
config :hotblock, packet_logger_enabled: false

# Serve the web panel on localhost:4000 when running iex -S mix
config :hotblock, HotblockWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  server: true,
  secret_key_base: "7XxroUxicDS4t4J5QYNgFNqKJZ9AyfEtjgWL5aISRlGMmHaobRRNWo1PC11dF6ih"
