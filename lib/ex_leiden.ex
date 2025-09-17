defmodule ExLeiden do
  @moduledoc """
  A pure Elixir implementation of the Leiden algorithm for community detection in networks.

  The main entry point is `call/2`, which accepts graph data as `{vertices, edges}` tuples and returns community detection results using the Leiden algorithm.

  See the [README](README.md) for detailed documentation, usage examples, and algorithm overview.
  """

  alias ExLeiden.Utils

  defmodule Behaviour do
    # Input format types
    @type vertex() :: term()
    @type edge() :: {vertex(), vertex()} | {vertex(), vertex(), weight :: number()}
    @type adjacency_matrix() :: [[number()]] | Nx.Tensor.t()

    # libgraph Graph struct
    @type input() ::
            Graph.t()
            # List of edges: [{v1, v2}, {v1, v2, weight}, ...]
            | [edge()]
            # Tuple: {vertices, edges}
            | {[vertex()], [edge()]}
            # 2D list for adjacency matrix
            | adjacency_matrix()

    @callback call(input(), keyword() | map()) ::
                {:ok, ExLeiden.Leiden.Behaviour.results()} | {:error, map()}
  end

  @behaviour Behaviour

  @doc """
  Detects communities in a network using the Leiden algorithm.

  ## Parameters

  - `input` - Graph data in one of these formats:
    - `%Graph{}` - libgraph Graph struct
    - `%Nx.Tensor{}` - adjacency matrix struct
    - `[{v1, v2}, ...]` - Edge list (unweighted)
    - `[{v1, v2, weight}, ...]` - Edge list (weighted)
    - `{vertices, edges}` - Explicit vertex and edge lists
    - `[[0, 1, 0], [1, 0, 1], ...]` - 2D adjacency matrix

  - `opts` - Algorithm options (see README.md for details)

  ## Options

    * `:quality_function` - Quality function to optimize (`:modularity` or `:cpm`).
      Defaults to `:modularity`.

    * `:resolution` - Resolution parameter γ controlling community granularity.
      Higher values favor smaller communities. Defaults to `1.0`.

    * `:max_level` - Maximum hierarchical levels to create.
      Algorithm may stop early if no improvements possible. Defaults to `5`.

    * `:community_size_threshold` - Minimum community size threshold for termination.
      If all communities are at or below this size, the algorithm will terminate.
      Takes precedence over `:max_level` when both are set. Defaults to `nil` (disabled).

  ## Returns

  - `{:ok, result}` - Success with community detection results and metadata
  - `{:error, reason}` - Invalid options or input validation error

  ## Examples

      iex> ExLeiden.call([{:a, :b}, {:b, :c}])
      {:ok, %{1 => {[%{id: 0, children: [0, 1, 2]}], []}}}

      iex> ExLeiden.call([[0, 1], [1, 0]], resolution: 0.5)
      {:ok, %{1 => {[%{id: 0, children: [0]}, %{id: 1, children: [1]}], []}}}
  """
  @impl true
  def call(input, opts \\ []) do
    with {:ok, validated_opts} <- Utils.module(:option).validate_opts(opts) do
      result =
        input
        |> Utils.module(:source).build!()
        |> Utils.module(:leiden).call(validated_opts)

      {:ok, result}
    end
  end
end
