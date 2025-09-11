defmodule ExLeiden.Leiden.Aggregate do
  alias ExLeiden.Utils
  alias ExLeiden.Source

  defmodule Behaviour do
    @callback call(Nx.Tensor.t(), Nx.Tensor.t()) :: Source.t()
  end

  @behaviour Behaviour
  @moduledoc """
  Implements the aggregation phase of the Leiden algorithm.

  The aggregation phase creates a new network where each community becomes
  a single node, and edges between communities become edges in the aggregate network.
  This allows the algorithm to operate hierarchically across multiple levels.
  """

  @doc """
  Create aggregate network from communities.

  ## Parameters

  - `adjacency_matrix` - The original adjacency matrix (n x n tensor)
  - `partition_matrix` - Community assignment matrix (n x c binary matrix)

  ## Returns

  A new Source struct representing the aggregate network where:
  - Each community becomes a single node
  - Only edges between different communities are preserved
  - Diagonal entries are zero (no self-loops)
  - Degree sequence is calculated from the aggregate adjacency matrix

  ## Algorithm

  1. Computes C^T * A * C where C is partition matrix, A is adjacency matrix
  2. Zeros out diagonal to remove internal community connections
  3. Creates new Source struct with aggregate adjacency matrix and degrees

  ## Examples

      # Path graph: 0---1---2---3 with communities {0,1} and {2,3}
      iex> adj = Nx.tensor([[0,1,0,0], [1,0,1,0], [0,1,0,1], [0,0,1,0]])
      iex> partition = Nx.tensor([[1,0], [1,0], [0,1], [0,1]])
      iex> %Source{} = ExLeiden.Leiden.Aggregate.call(adj, partition)
      # Returns Source with 2x2 adjacency matrix [[0,1], [1,0]] and degrees [1,1]
  """
  @impl true
  def call(adjacency_matrix, partition_matrix) do
    # Create aggregate adjacency matrix: C^T * A * C
    # where C is the partition matrix and A is the adjacency matrix
    aggregate_matrix =
      partition_matrix
      # C^T (c x n)
      |> Nx.transpose()
      # C^T * A (c x n)
      |> Nx.dot(adjacency_matrix)
      # C^T * A * C (c x c)
      |> Nx.dot(partition_matrix)

    # Zero out diagonal (remove self-loops/internal edges)
    # We only want edges between communities, not within communities
    {n_communities, _} = Nx.shape(aggregate_matrix)
    diagonal_mask = Nx.eye(n_communities)

    # Set diagonal to 0: keep only inter-community edges
    new_adjacency_matrix = Nx.select(diagonal_mask, 0, aggregate_matrix)
    Utils.module(:source).build!(new_adjacency_matrix)
  end
end
