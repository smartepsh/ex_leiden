defmodule ExLeiden.Quality.Modularity do
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
    - `current_node` - Index of the node to find best move for
    - `community_matrix` - Current community assignment matrix (n x c binary matrix)
    - `total_edges` - Total edge weight in the graph (scalar)
    - `opts` - Options including `:resolution` parameter (default: 1.0)

  ## Returns

    A map containing:
    - `:best_community` - Community index with highest delta
    - `:delta_q` - Modularity delta value for the best move
    - `:current_community` - Node's current community index

  ## Examples

      iex> adjacency = Nx.tensor([[0, 1, 1], [1, 0, 0], [1, 0, 0]])
      iex> community_matrix = Nx.eye(3)  # Each node in own community
      iex> {best_community, delta_q} = ExLeiden.Quality.Modularity.best_move(adjacency, 0, community_matrix, 2.0)

  """
  @spec best_move(
          adjacency_matrix :: Nx.Tensor.t(),
          node_index :: non_neg_integer(),
          community_matrix :: Nx.Tensor.t(),
          network_total_edges :: number(),
          opts :: keyword()
        ) :: {best_community :: non_neg_integer(), best_delta_q :: float()}
  def best_move(_adjacency_matrix, current_node, community_matrix, 0, _opts) do
    # Empty graph case - no edges, no meaningful moves
    current_community = find_current_community(community_matrix, current_node)
    {current_community, 0.0}
  end

  def best_move(adjacency_matrix, current_node, community_matrix, total_edges, opts) do
    resolution = Keyword.fetch!(opts, :resolution)

    # Find current community of the node
    current_community = find_current_community(community_matrix, current_node)

    # Get node's degree and adjacency row
    node_degree = calculate_node_degree(adjacency_matrix, current_node)
    node_row = adjacency_matrix[current_node]

    # Calculate edges from current node to each community
    edges_to_communities = calculate_edges_to_communities(node_row, community_matrix)

    # Calculate community degrees
    community_degrees = calculate_community_degrees(adjacency_matrix, community_matrix)

    # Find best move by calculating deltas for all communities
    {n_communities} = Nx.shape(community_degrees)

    {best_community, best_delta} =
      0..(n_communities - 1)
      |> Enum.map(fn community_idx ->
        delta =
          calculate_modularity_delta(
            current_node,
            current_community,
            community_idx,
            node_degree,
            edges_to_communities,
            community_degrees,
            total_edges,
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

  # Calculate the degree of a specific node
  defp calculate_node_degree(adjacency_matrix, node_idx) do
    adjacency_matrix[node_idx]
    |> Nx.sum()
    |> Nx.to_number()
  end

  # Calculate edges from a node to each community
  defp calculate_edges_to_communities(node_row, community_matrix) do
    # node_row × community_matrix = edges to each community
    # Nx handles vector-matrix multiplication automatically
    Nx.dot(node_row, community_matrix)
  end

  # Calculate total degree for each community
  defp calculate_community_degrees(adjacency_matrix, community_matrix) do
    adjacency_matrix
    |> Nx.sum(axes: [1])
    |> Nx.dot(community_matrix)
  end

  # Calculate modularity delta for moving a node from current to target community
  defp calculate_modularity_delta(_, community, community, _, _, _, _, _), do: 0.0

  defp calculate_modularity_delta(
         node_idx,
         current_community,
         target_community,
         node_degree,
         edges_to_communities,
         community_degrees,
         total_edges,
         resolution
       ) do
    # Extract values
    k_i = node_degree
    k_i_in_current = Nx.to_number(edges_to_communities[current_community])
    k_i_in_target = Nx.to_number(edges_to_communities[target_community])
    k_current = Nx.to_number(community_degrees[current_community])
    k_target = Nx.to_number(community_degrees[target_community])

    # Calculate modularity delta
    # ΔQ = (1/2m) * [k_i_in_new - k_i_in_old - γ * k_i * (K_new - K_old + k_i) / (2m)]
    # Note: No need to exclude self-edges since adjacency matrix diagonal is typically 0
    actual_edge_delta = k_i_in_target - k_i_in_current

    # Community degree changes (excluding the moving node's contribution)
    k_current_without_node = k_current - k_i
    k_target_with_node = k_target + k_i

    expected_edge_delta =
      resolution * k_i * (k_target_with_node - k_current_without_node) / (2 * total_edges)

    (actual_edge_delta - expected_edge_delta) / (2 * total_edges)
  end
end
