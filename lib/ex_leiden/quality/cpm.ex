defmodule ExLeiden.Quality.CPM do
  @behaviour ExLeiden.Quality.Behaviour

  @moduledoc """
  Constant Potts Model (CPM) quality function for the Leiden algorithm.

  This module implements CPM-based community detection calculations,
  providing the best move analysis for nodes in the local moving phase.

  CPM measures community quality by optimizing internal edges minus a resolution penalty.
  The CPM delta formula used here is:
  ΔQ = (edges_to_new - edges_to_old) - γ * (size_new - size_old + 1)

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
    - `community_matrix` - Current community assignment matrix (n x c binary matrix)
    - `total_edges` - Total edge weight in the graph (scalar)
    - `opts` - Options including `:resolution` parameter (default: 1.0)

  ## Returns

    A tuple containing:
    - `best_community` - Community index with highest delta
    - `best_delta` - CPM delta value for the best move

  ## Examples

      iex> adjacency = Nx.tensor([[0, 1, 1], [1, 0, 0], [1, 0, 0]])
      iex> community_matrix = Nx.eye(3)  # Each node in own community
      iex> {best_community, delta_q} = ExLeiden.Quality.CPM.best_move(adjacency, 0, community_matrix, 2.0, [resolution: 1.0])

  """
  @spec best_move(
          adjacency_matrix :: Nx.Tensor.t(),
          node_index :: non_neg_integer(),
          community_matrix :: Nx.Tensor.t(),
          network_total_edges :: number(),
          opts :: keyword()
        ) :: {best_community :: non_neg_integer(), best_delta_q :: float()}
  @impl true
  def best_move(_adjacency_matrix, current_node, community_matrix, 0, _opts) do
    # Empty graph case - no edges, no meaningful moves
    current_community = find_current_community(community_matrix, current_node)
    {current_community, 0.0}
  end

  def best_move(adjacency_matrix, current_node, community_matrix, _total_edges, opts) do
    resolution = Keyword.fetch!(opts, :resolution)

    # Find current community of the node
    current_community = find_current_community(community_matrix, current_node)

    # Get node's adjacency row
    node_row = adjacency_matrix[current_node]

    # Calculate edges from current node to each community
    edges_to_communities = calculate_edges_to_communities(node_row, community_matrix)

    # Calculate community sizes
    community_sizes = calculate_community_sizes(community_matrix)

    # Find best move by calculating deltas for all communities
    {n_communities} = Nx.shape(community_sizes)

    {best_community, best_delta} =
      0..(n_communities - 1)
      |> Enum.map(fn community_idx ->
        delta =
          calculate_cpm_delta(
            current_community,
            community_idx,
            edges_to_communities,
            community_sizes,
            resolution
          )

        {community_idx, delta}
      end)
      |> Enum.max_by(fn {_community, delta} -> delta end)

    {best_community, best_delta}
  end

  # Find which community a node currently belongs to
  defp find_current_community(community_matrix, node_idx) do
    community_matrix[node_idx]
    |> Nx.argmax()
    |> Nx.to_number()
  end

  # Calculate edges from a node to each community
  defp calculate_edges_to_communities(node_row, community_matrix) do
    # node_row × community_matrix = edges to each community
    # Nx handles vector-matrix multiplication automatically
    Nx.dot(node_row, community_matrix)
  end

  # Calculate number of nodes in each community
  defp calculate_community_sizes(community_matrix) do
    # Sum each column to get community sizes
    Nx.sum(community_matrix, axes: [0])
  end

  # Calculate CPM delta for moving a node from current to target community
  defp calculate_cpm_delta(community, community, _, _, _), do: 0.0

  defp calculate_cpm_delta(
         current_community,
         target_community,
         edges_to_communities,
         community_sizes,
         resolution
       ) do
    # Extract values
    edges_to_current = Nx.to_number(edges_to_communities[current_community])
    edges_to_target = Nx.to_number(edges_to_communities[target_community])
    size_current = Nx.to_number(community_sizes[current_community])
    size_target = Nx.to_number(community_sizes[target_community])

    # Calculate CPM delta
    # ΔQ = (edges_to_new - edges_to_old) - γ * (size_new - size_old + 1)
    edge_delta = edges_to_target - edges_to_current
    size_penalty = resolution * (size_target - size_current + 1)

    edge_delta - size_penalty
  end
end
