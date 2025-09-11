defmodule ExLeiden.Quality.CPM do
  @behaviour ExLeiden.Quality.Behaviour

  @moduledoc """
  Constant Potts Model (CPM) quality function for the Leiden algorithm.

  This module implements CPM-based community detection calculations,
  providing the best move analysis for nodes in the local moving phase.

  CPM measures community quality by optimizing internal edges minus a resolution penalty.
  The CPM delta formula used here is:
  ΔQ = (edges_to_new - edges_to_old) - γ * (size_new - size_old + 1) / 2

  Where:
  - edges_to_new/old are edges from node i to new/old communities
  - size_new/old are the number of nodes in new/old communities
  - γ is the resolution parameter
  """

  @doc """
  Find the best community move for a single node.

  Calculates the CPM delta for all possible community moves for the
  given node and returns the move with the highest delta (even if negative).

  ## Parameters

    - `adjacency_matrix` - The adjacency matrix of the graph (n x n tensor)
    - `current_node` - Index of the node to find best move for
    - `partition_matrix` - Current community assignment matrix (n x c binary matrix)
    - `total_edges` - Total edge weight in the graph (scalar)
    - `opts` - Options including `:resolution` parameter (default: 1.0)

  ## Returns

    A tuple containing:
    - `best_community` - Community index with highest delta
    - `best_delta` - CPM delta value for the best move

  ## Examples

      iex> adjacency = Nx.tensor([[0, 1, 1], [1, 0, 0], [1, 0, 0]])
      iex> partition_matrix = Nx.eye(3)  # Each node in own community
      iex> {best_community, delta_q} = ExLeiden.Quality.CPM.best_move(adjacency, 0, partition_matrix, 2.0, [resolution: 1.0])

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
    # Empty graph case - no edges, no meaningful moves
    current_community =
      partition_matrix[node_index]
      |> Nx.argmax()
      |> Nx.to_number()

    {current_community, 0.0}
  end

  def best_move(adjacency_matrix, node_index, partition_matrix, total_edges, opts) do
    deltas = delta_gains(adjacency_matrix, node_index, partition_matrix, total_edges, opts)

    best_community = deltas |> Nx.argmax() |> Nx.to_number()
    best_gain = deltas[best_community] |> Nx.to_number()

    {best_community, best_gain}
  end

  @doc """
  Calculate CPM delta gains for moving a node from current community to all communities.

  This function calculates the complete quality delta for moving a node to each community,
  accounting for both the gain from joining the target and loss from leaving current.

  CPM Quality: Q = Σ[e_c - γ * n_c / 2]
  Complete Delta: ΔQ = (edges_to_target - edges_to_current) - γ * (n_target - n_current + 1) / 2

  ## Parameters

    - `adjacency_matrix` - The adjacency matrix of the graph (n x n tensor)
    - `node_index` - Index of the node to calculate deltas for
    - `partition_matrix` - Community assignment matrix (n x c binary matrix)
    - `total_edges` - Total edge weight in the graph (unused in CPM)
    - `opts` - Options including `:resolution` parameter

  ## Returns

    A tensor of complete quality deltas for each community (c-dimensional tensor)

  """
  @spec delta_gains(
          adjacency_matrix :: Nx.Tensor.t(),
          node_index :: non_neg_integer(),
          partition_matrix :: Nx.Tensor.t(),
          total_edges :: number(),
          opts :: keyword
        ) :: Nx.Tensor.t()
  @impl true
  def delta_gains(adjacency_matrix, node_index, partition_matrix, _total_edges, opts) do
    resolution = Keyword.fetch!(opts, :resolution)

    # Get node's adjacency row
    node_row = adjacency_matrix[node_index]

    # Calculate edges from node to ALL communities at once
    edges_to_all_communities = Nx.dot(node_row, partition_matrix)

    # Get all community sizes
    all_community_sizes = Nx.sum(partition_matrix, axes: [0])

    # Find current community of the node using actual node index
    current_community_mask = partition_matrix[node_index]
    current_community_idx = Nx.argmax(current_community_mask)

    # Get edges to current community and current community size (keep as tensors)
    edges_to_current = Nx.take(edges_to_all_communities, current_community_idx)
    current_community_size = Nx.take(all_community_sizes, current_community_idx)

    # Calculate sizes after move
    target_sizes_after = Nx.add(all_community_sizes, 1)
    current_size_after = Nx.subtract(current_community_size, 1)

    # Calculate penalty changes using tensor operations (CPM uses linear size, not squared)
    penalty_changes =
      target_sizes_after
      |> Nx.subtract(current_size_after)
      |> Nx.divide(2)
      |> Nx.multiply(resolution)

    # Create mask for current community (self-move case)
    current_community_mask =
      Nx.equal(Nx.iota({Nx.axis_size(all_community_sizes, 0)}), current_community_idx)

    # Set self-move penalty to 0
    penalty_changes = Nx.select(current_community_mask, 0, penalty_changes)

    # Complete CPM delta: (edges_to_target - edges_to_current) - penalty_change
    edges_to_all_communities
    |> Nx.subtract(edges_to_current)
    |> Nx.subtract(penalty_changes)
  end
end
