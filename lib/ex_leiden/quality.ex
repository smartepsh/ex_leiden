defmodule ExLeiden.Quality do
  @moduledoc """
  Quality functions for community detection in networks.

  Implements both Modularity and Constant Potts Model (CPM) quality functions
  using efficient matrix operations for scalable computation.
  """

  @doc """
  Calculate the modularity quality function.

  Modularity measures the strength of division of a network into communities.
  Higher modularity indicates stronger community structure.

  Formula: H = (1/2m) * Σ_c (e_c - γ * K_c²/(2m))

  Where:
  - e_c = number of edges within community c
  - K_c = sum of degrees of nodes in community c  
  - m = total number of edges in network
  - γ = resolution parameter (default: 1.0)
  """
  @spec modularity(Nx.Tensor.t(), list(), number()) :: number()
  def modularity(adjacency_matrix, communities, gamma \\ 1.0) do
    m = total_edges(adjacency_matrix)
    degree_sequence = Nx.sum(adjacency_matrix, axes: [1])

    # Get unique communities and compute modularity for each
    unique_communities = communities |> Enum.uniq() |> Enum.sort()

    community_modularities =
      unique_communities
      |> Enum.map(fn community ->
        community_modularity(adjacency_matrix, degree_sequence, communities, community, m, gamma)
      end)

    # Sum all community modularities and normalize by 2m
    community_modularities
    |> Enum.sum()
    |> then(&(&1 / (2 * m)))
  end

  @doc """
  Calculate the Constant Potts Model (CPM) quality function.

  CPM is resolution-limit-free and finds communities by optimizing
  the difference between actual and expected edges in complete subgraphs.

  Formula: H = Σ_c (e_c - γ * n_c * (n_c - 1) / 2)

  Where:
  - e_c = number of edges within community c
  - n_c = number of nodes in community c
  - γ = resolution parameter (default: 1.0)
  """
  @spec cpm(Nx.Tensor.t(), list(), number()) :: number()
  def cpm(adjacency_matrix, communities, gamma \\ 1.0) do
    unique_communities = communities |> Enum.uniq() |> Enum.sort()

    community_cpm_values =
      unique_communities
      |> Enum.map(fn community ->
        community_cpm(adjacency_matrix, communities, community, gamma)
      end)

    Enum.sum(community_cpm_values)
  end

  @doc """
  Calculate quality gain for moving a node between communities.

  This is used in the local moving phase to determine beneficial moves.
  """
  @spec quality_gain(atom(), Nx.Tensor.t(), list(), integer(), integer(), integer(), number()) ::
          number()
  def quality_gain(
        quality_function,
        adjacency_matrix,
        communities,
        node_idx,
        from_community,
        to_community,
        gamma \\ 1.0
      ) do
    case quality_function do
      :modularity ->
        modularity_gain(
          adjacency_matrix,
          communities,
          node_idx,
          from_community,
          to_community,
          gamma
        )

      :cpm ->
        cpm_gain(adjacency_matrix, communities, node_idx, from_community, to_community, gamma)
    end
  end

  # Private helper functions

  defp total_edges(adjacency_matrix) do
    adjacency_matrix |> Nx.sum() |> Nx.to_number() |> Kernel./(2)
  end

  defp community_modularity(adjacency_matrix, degree_sequence, communities, community, m, gamma) do
    community_nodes = get_community_nodes(communities, community)

    if length(community_nodes) == 0 do
      0.0
    else
      # Calculate internal edges (e_c)
      internal_edges = calculate_internal_edges(adjacency_matrix, community_nodes)

      # Calculate sum of degrees (K_c)
      community_degree_sum =
        community_nodes
        |> Enum.map(&Nx.to_number(degree_sequence[&1]))
        |> Enum.sum()

      # Modularity for this community: e_c - γ * K_c²/(2m)
      internal_edges - gamma * (community_degree_sum * community_degree_sum) / (2 * m)
    end
  end

  defp community_cpm(adjacency_matrix, communities, community, gamma) do
    community_nodes = get_community_nodes(communities, community)
    community_size = length(community_nodes)

    if community_size <= 1 do
      0.0
    else
      # Calculate internal edges (e_c)
      internal_edges = calculate_internal_edges(adjacency_matrix, community_nodes)

      # Expected edges in complete graph: C(n,2) = n*(n-1)/2
      expected_edges = community_size * (community_size - 1) / 2

      # CPM for this community: e_c - γ * C(n_c, 2)
      internal_edges - gamma * expected_edges
    end
  end

  defp get_community_nodes(communities, target_community) do
    communities
    |> Enum.with_index()
    |> Enum.filter(fn {community, _idx} -> community == target_community end)
    |> Enum.map(fn {_community, idx} -> idx end)
  end

  defp calculate_internal_edges(adjacency_matrix, community_nodes) do
    if length(community_nodes) <= 1 do
      0.0
    else
      # Extract submatrix for community nodes
      indices = Nx.tensor(community_nodes)

      submatrix =
        adjacency_matrix
        |> Nx.take(indices, axis: 0)
        |> Nx.take(indices, axis: 1)

      # Sum all edges and divide by 2 (since matrix is symmetric)
      submatrix |> Nx.sum() |> Nx.to_number() |> Kernel./(2)
    end
  end

  # Quality gain calculations for local moving phase

  defp modularity_gain(
         adjacency_matrix,
         communities,
         node_idx,
         from_community,
         to_community,
         gamma
       ) do
    if from_community == to_community do
      0.0
    else
      degree_sequence = Nx.sum(adjacency_matrix, axes: [1])
      m = total_edges(adjacency_matrix)
      node_degree = Nx.to_number(degree_sequence[node_idx])

      # Connections from node to each community
      from_connections =
        connections_to_community(adjacency_matrix, communities, node_idx, from_community)

      to_connections =
        connections_to_community(adjacency_matrix, communities, node_idx, to_community)

      # Community degree sums (excluding the moving node)
      from_degree_sum =
        community_degree_sum(degree_sequence, communities, from_community) - node_degree

      to_degree_sum = community_degree_sum(degree_sequence, communities, to_community)

      # Modularity gain calculation
      edge_gain = to_connections - from_connections
      degree_penalty = gamma * node_degree * (to_degree_sum - from_degree_sum) / m

      (edge_gain - degree_penalty) / (2 * m)
    end
  end

  defp cpm_gain(adjacency_matrix, communities, node_idx, from_community, to_community, gamma) do
    if from_community == to_community do
      0.0
    else
      # Connections from node to each community  
      from_connections =
        connections_to_community(adjacency_matrix, communities, node_idx, from_community)

      to_connections =
        connections_to_community(adjacency_matrix, communities, node_idx, to_community)

      # Community sizes (excluding the moving node for from_community)
      from_size = community_size(communities, from_community) - 1
      to_size = community_size(communities, to_community)

      # CPM gain calculation
      edge_gain = to_connections - from_connections
      size_penalty = gamma * (to_size - from_size)

      edge_gain - size_penalty
    end
  end

  defp connections_to_community(adjacency_matrix, communities, node_idx, target_community) do
    # Get connections from node to all other nodes
    node_row = Nx.take(adjacency_matrix, node_idx, axis: 0)

    # Sum connections to nodes in target community
    communities
    |> Enum.with_index()
    |> Enum.reduce(0.0, fn {community, idx}, acc ->
      if community == target_community and idx != node_idx do
        acc + Nx.to_number(node_row[idx])
      else
        acc
      end
    end)
  end

  defp community_degree_sum(degree_sequence, communities, target_community) do
    communities
    |> Enum.with_index()
    |> Enum.reduce(0.0, fn {community, idx}, acc ->
      if community == target_community do
        acc + Nx.to_number(degree_sequence[idx])
      else
        acc
      end
    end)
  end

  defp community_size(communities, target_community) do
    communities |> Enum.count(&(&1 == target_community))
  end
end
