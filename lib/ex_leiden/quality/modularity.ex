defmodule ExLeiden.Quality.Modularity do
  @behaviour ExLeiden.Quality.Behaviour
  import Nx.Defn

  @moduledoc """
  Modularity quality function for the Leiden algorithm.

  This module implements modularity-based community detection calculations,
  providing the best move analysis for nodes in the local moving phase.

  Modularity measures the strength of division of a network into communities.
  The modularity delta formula used here is:
  ΔQ = (1/2m) * [k_i_in_new - k_i_in_old - γ * k_i * (K_new - K_old + k_i) / (2m)]

  Where:
  - k_i is the degree of node i
  - k_i_in_new/old are edges from node i to new/old communities
  - K_new/old are total degrees in new/old communities
  - γ is the resolution parameter
  - m is the total edge weight
  """

  @doc """
  Find the best community move for a single node.

  Calculates the modularity delta for all possible community moves for the
  given node and returns the move with the highest delta (even if negative).

  ## Parameters

    - `adjacency_matrix` - The adjacency matrix of the graph (n x n tensor)
    - `node_index` - Index of the node to find best move for
    - `partition_matrix` - Current community assignment matrix (n x c binary matrix)
    - `total_edges` - Total edge weight in the graph (scalar)
    - `opts` - Options including `:resolution` parameter (default: 1.0)

  ## Returns

    A tuple containing:
    - `best_community` - Community index with highest delta (non_neg_integer)
    - `best_delta_q` - Modularity delta value for the best move (float)

  ## Examples

      iex> adjacency = Nx.tensor([[0, 1, 1], [1, 0, 0], [1, 0, 0]])
      iex> partition_matrix = Nx.eye(3)  # Each node in own community
      iex> {best_community, delta_q} = ExLeiden.Quality.Modularity.best_move(adjacency, 0, partition_matrix, 2.0, resolution: 1.0)
      iex> best_community
      iex> delta_q

  """
  @spec best_move(
          adjacency_matrix :: Nx.Tensor.t(),
          node_index :: non_neg_integer(),
          partition_matrix :: Nx.Tensor.t(),
          network_total_edges :: number(),
          opts :: keyword()
        ) :: {best_community :: non_neg_integer(), best_delta_q :: float()}
  @impl true
  def best_move(_adjacency_matrix, node_index, partition_matrix, 0, _opts) do
    # Empty graph case - no edges, no meaningful moves possible
    # Node stays in current community with zero modularity change
    current_community = find_current_community(partition_matrix, node_index) |> Nx.to_number()

    {current_community, 0.0}
  end

  def best_move(adjacency_matrix, node_index, partition_matrix, total_edges, opts) do
    deltas = delta_gains(adjacency_matrix, node_index, partition_matrix, total_edges, opts)

    # Find the index of the maximum value
    best_community = deltas |> Nx.argmax() |> Nx.to_number()
    best_delta_q = deltas[best_community] |> Nx.to_number()

    {best_community, best_delta_q}
  end

  @impl true
  def delta_gains(adjacency_matrix, node_index, partition_matrix, total_edges, opts_or_resolution)

  def delta_gains(adjacency_matrix, node_index, partition_matrix, total_edges, opts)
      when is_list(opts) do
    resolution = Keyword.fetch!(opts, :resolution)
    delta_gains_impl(adjacency_matrix, node_index, partition_matrix, total_edges, resolution)
  end

  def delta_gains(adjacency_matrix, node_index, partition_matrix, total_edges, resolution)
      when is_number(resolution) do
    delta_gains_impl(adjacency_matrix, node_index, partition_matrix, total_edges, resolution)
  end

  defnp delta_gains_impl(adjacency_matrix, node_index, partition_matrix, total_edges, resolution) do
    # Find current community of the node
    current_community = find_current_community(partition_matrix, node_index)

    # Get node's degree and adjacency row
    node_degree = calculate_node_degree(adjacency_matrix, node_index)
    node_row = adjacency_matrix[node_index]

    # Calculate edges from current node to each community
    edges_to_communities = calculate_edges_to_communities(node_row, partition_matrix)

    # Calculate community degrees
    community_degrees = calculate_community_degrees(adjacency_matrix, partition_matrix)

    # Matrix-based calculation for all communities at once - returns 1-D tensor
    calculate_all_modularity_deltas_matrix(
      current_community,
      node_degree,
      edges_to_communities,
      community_degrees,
      total_edges,
      resolution
    )
  end

  # Find which community a node currently belongs to
  defnp find_current_community(partition_matrix, node_idx) do
    Nx.argmax(partition_matrix[node_idx])
  end

  # Calculate the degree of a specific node
  defnp calculate_node_degree(adjacency_matrix, node_idx) do
    Nx.sum(adjacency_matrix[node_idx])
  end

  # Calculate edges from a node to each community
  defnp calculate_edges_to_communities(node_row, partition_matrix) do
    # node_row × partition_matrix = edges to each community
    # Nx handles vector-matrix multiplication automatically
    Nx.dot(node_row, partition_matrix)
  end

  # Calculate total degree for each community
  defnp calculate_community_degrees(adjacency_matrix, partition_matrix) do
    adjacency_matrix
    |> Nx.sum(axes: [1])
    |> Nx.dot(partition_matrix)
  end

  # Calculate modularity deltas for all communities using matrix operations
  defnp calculate_all_modularity_deltas_matrix(
          current_community,
          node_degree,
          edges_to_communities,
          community_degrees,
          total_edges,
          resolution
        ) do
    k_i = node_degree
    k_i_in_current = edges_to_communities[current_community]

    # Vectorized calculations for all communities
    actual_edge_deltas = Nx.subtract(edges_to_communities, k_i_in_current)

    # Community degree changes for all communities
    k_current = community_degrees[current_community]
    k_i_in_new = Nx.add(community_degrees, k_i)

    # Calculate k_current_without_node using tensor operations
    k_current_without_node = Nx.subtract(k_current, k_i)

    # Calculate expected edge changes: γ * k_i * (K_new - K_old + k_i) / (2m)
    expected_edge_deltas =
      k_i_in_new
      # (K_new - K_old + k_i)
      |> Nx.subtract(k_current_without_node)
      # γ * k_i * (K_new - K_old + k_i)
      |> Nx.multiply(Nx.multiply(k_i, resolution))
      # / (2m)
      |> Nx.divide(Nx.multiply(2, total_edges))

    # Final delta calculation: (1/2m) * [actual_edge_deltas - expected_edge_deltas]
    deltas =
      actual_edge_deltas
      |> Nx.subtract(expected_edge_deltas)
      |> Nx.divide(Nx.multiply(2, total_edges))

    # Create mask for current community (self-move case)
    current_community_mask =
      Nx.equal(Nx.iota({Nx.axis_size(deltas, 0)}), current_community)

    # Set self-move delta to 0 using Nx.select (staying in same community = no change)
    Nx.select(current_community_mask, 0, deltas)
  end
end
