defmodule ExLeiden.MixProject do
  use Mix.Project

  @version "0.0.3"
  @source_url "https://github.com/smartepsh/ex_leiden"

  def project do
    [
      app: :ex_leiden,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "ExLeiden",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ExLeiden.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Core dependencies
      {:libgraph, "~> 0.16"},
      {:nx, "~> 0.10"},

      # Development and testing dependencies
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end

  defp description do
    """
    A pure Elixir implementation of the Leiden algorithm for community detection in networks.
    The Leiden algorithm improves upon the Louvain method by addressing resolution limits and ensuring well-connected communities. Supports both modularity and CPM quality functions.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Docs" => "https://hexdocs.pm/ex_leiden",
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "Arxiv" => "https://arxiv.org/abs/1810.08473",
        "Doi" => "https://doi.org/10.1038/s41598-019-41695-z"
      },
      maintainers: ["Kenton Wang"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md"
      ],
      groups_for_modules: []
    ]
  end
end
