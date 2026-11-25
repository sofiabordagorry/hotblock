import Config

# Tests use a different port so they can run while the real server is up
config :hotblock, server_port: 25576

config :hotblock, packet_logger_enabled: false

# Tests talk to the endpoint directly, so it does not open a port
config :hotblock, HotblockWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false,
  secret_key_base: "r2WndAdZbUwih6Sqp1zyrkc5F4wKfSVS4mKTDJ7F4DOELxdVju5J3gq2r2yVHnh2"

config :hotblock, admin_token: "test-token"

# No limit between effects, so the tests can send them one after another
config :hotblock, effect_cooldown_ms: 0

# The poller resets the packet counters, so in the tests it barely runs
config :hotblock, telemetry_period: :timer.hours(1)

# Only show warnings and errors in the tests
config :logger, level: :warning
