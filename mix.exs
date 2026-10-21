defmodule Llamex.MixProject do
  use Mix.Project

  def project do
    [
      app: :llamex,
      version: "0.1.0",
      elixir: "~> 1.19",
      description:
        "Credo checks for issues commonly introduced by LLM-assisted Elixir refactorings",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.7"},
      {:ash, "~> 3.29", optional: true},
      {:mdex, "~> 0.14", optional: true}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/llamex/llamex"}
    ]
  end
end
