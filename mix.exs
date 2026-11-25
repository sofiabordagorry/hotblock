defmodule Hotblock.MixProject do
  use Mix.Project

  def project do
    [
      app: :hotblock,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Hotblock.Application, []}
    ]
  end

  # The test helpers in test/support are compiled only for the tests
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.2"},
      {:bandit, "~> 1.15"},
      {:lazy_html, "~> 0.1.0", only: :test},
      # Property tests: generates many random inputs for each test
      {:stream_data, "~> 1.1", only: [:dev, :test]}
    ]
  end
end
