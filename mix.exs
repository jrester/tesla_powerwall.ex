defmodule TeslaPowerwall.MixProject do
  use Mix.Project

  @version "0.1.1"
  @repo_url "https://github.com/jrester/tesla_powerwall.ex"

  def project do
    [
      app: :tesla_powerwall,
      version: @version,
      elixir: "~> 1.10",
      description: description(),
      package: package(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:finch, "~> 0.3"},
      {:jason, "~> 1.0"},
      {:ex_doc, "~> 0.22", only: :dev, runtime: false},
    ]
  end

  defp description do
    "API for the Tesla Powerwall"
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"Github" => @repo_url}
    ]
  end
end
