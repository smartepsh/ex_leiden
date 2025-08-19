defmodule ExLeiden.Aggregation do
  @moduledoc """
  Aggregation phase of the Leiden algorithm.

  This phase creates a new network where communities become nodes,
  and edges between communities become edges in the aggregate network.
  This enables hierarchical community detection across multiple levels.
  """

  @doc """
  Perform the aggregation phase.

  Creates an aggregate network where:
  - Each community becomes a single node
  - Edge weights between communities are summed
  - Self-loops (within community edges) are removed

  Returns {aggregate_adjacency_matrix, community_mapping}
  """
  @spec aggregate_network(Nx.Tensor.t(), list()) :: {Nx.Tensor.t(), map()}
  def aggregate_network(adjacency_matrix, communities) do
    unique_communities = communities |> Enum.uniq() |> Enum.sort()
    n_communities = length(unique_communities)

    # Create mapping from community ID to matrix index
    community_to_index =
      unique_communities
      |> Enum.with_index()
      |> Map.new()

    # Create aggregate adjacency matrix
    aggregate_matrix =
      build_aggregate_matrix(adjacency_matrix, communities, community_to_index, n_communities)

    # Return the aggregate matrix and the mapping for reconstruction
    {aggregate_matrix,
     %{
       community_to_index: community_to_index,
       index_to_community:
         unique_communities |> Enum.with_index() |> Enum.map(fn {c, i} -> {i, c} end) |> Map.new(),
       original_communities: communities
     }}
  end

  @doc """
  Build the initial community assignments for the aggregate network.

  Each community in the aggregate network starts in its own community
  (singleton communities for the next iteration).
  """
  @spec initial_aggregate_communities(map()) :: list()
  def initial_aggregate_communities(community_mapping) do
    n_communities = map_size(community_mapping.community_to_index)
    0..(n_communities - 1) |> Enum.to_list()
  end

  @doc """
  Map aggregate communities back to original node communities.

  Takes the community assignments from the aggregate network and maps
  them back to the original nodes to create hierarchical community structure.
  """
  @spec map_back_to_original(list(), map(), integer()) :: list()
  def map_back_to_original(aggregate_communities, community_mapping, level) do
    original_communities = community_mapping.original_communities
    index_to_community = community_mapping.index_to_community
    community_to_index = community_mapping.community_to_index

    # Create hierarchical community IDs
    original_communities
    |> Enum.map(fn original_community ->
      # Get the index of this community in the aggregate matrix
      aggregate_index = Map.get(community_to_index, original_community)

      # Get the new community assignment for this aggregate node
      new_aggregate_community = Enum.at(aggregate_communities, aggregate_index)

      # Create hierarchical community ID
      {level, new_aggregate_community}
    end)
  end

  @doc """
  Calculate the total weight between two communities.

  Sums all edge weights between nodes in community1 and nodes in community2.
  """
  @spec inter_community_weight(Nx.Tensor.t(), list(), any(), any()) :: number()
  def inter_community_weight(adjacency_matrix, communities, community1, community2) do
    nodes1 = get_community_nodes(communities, community1)
    nodes2 = get_community_nodes(communities, community2)

    if community1 == community2 or length(nodes1) == 0 or length(nodes2) == 0 do
      0.0
    else
      # Sum all edges between the two communities
      Enum.reduce(nodes1, 0.0, fn node1, acc1 ->
        Enum.reduce(nodes2, acc1, fn node2, acc2 ->
          weight = adjacency_matrix |> Nx.take(node1, axis: 0) |> Nx.take(node2) |> Nx.to_number()
          acc2 + weight
        end)
      end)
    end
  end

  @doc """
  Get statistics about the aggregation phase.
  """
  @spec aggregation_stats(Nx.Tensor.t(), Nx.Tensor.t(), map()) :: map()
  def aggregation_stats(original_matrix, aggregate_matrix, community_mapping) do
    original_nodes = original_matrix |> Nx.shape() |> elem(0)
    aggregate_nodes = aggregate_matrix |> Nx.shape() |> elem(0)

    original_edges = original_matrix |> Nx.sum() |> Nx.to_number() |> Kernel./(2)
    aggregate_edges = aggregate_matrix |> Nx.sum() |> Nx.to_number() |> Kernel./(2)

    compression_ratio = original_nodes / max(aggregate_nodes, 1)

    %{
      original_nodes: original_nodes,
      aggregate_nodes: aggregate_nodes,
      original_edges: original_edges,
      aggregate_edges: aggregate_edges,
      compression_ratio: compression_ratio,
      communities_formed: aggregate_nodes
    }
  end

  @doc """
  Check if aggregation should continue.

  Aggregation should stop if:
  - Only one community remains
  - No significant compression was achieved
  - Maximum levels reached
  """
  @spec should_continue_aggregation?(map(), integer(), integer()) :: boolean()
  def should_continue_aggregation?(community_mapping, level, max_levels) do
    n_communities = map_size(community_mapping.community_to_index)

    cond do
      level >= max_levels -> false
      # Only one community left
      n_communities <= 1 -> false
      # Poor compression
      n_communities >= 0.8 * length(community_mapping.original_communities) -> false
      true -> true
    end
  end

  # Private helper functions

  defp build_aggregate_matrix(adjacency_matrix, communities, community_to_index, n_communities) do
    # Initialize aggregate matrix with zeros
    aggregate_matrix = Nx.broadcast(0.0, {n_communities, n_communities})

    # Calculate weights between all pairs of communities
    community_pairs =
      for i <- 0..(n_communities - 1),
          j <- 0..(n_communities - 1),
          # Exclude diagonal (self-loops)
          i != j,
          do: {i, j}

    # Build the matrix by calculating inter-community weights
    Enum.reduce(community_pairs, aggregate_matrix, fn {i, j}, matrix ->
      community_i = community_to_index |> Enum.find(fn {_c, idx} -> idx == i end) |> elem(0)
      community_j = community_to_index |> Enum.find(fn {_c, idx} -> idx == j end) |> elem(0)

      weight = inter_community_weight(adjacency_matrix, communities, community_i, community_j)

      # Set the weight in the aggregate matrix
      if weight > 0 do
        indices = Nx.tensor([[i, j]])
        Nx.indexed_put(matrix, indices, Nx.tensor([weight]))
      else
        matrix
      end
    end)
  end

  defp get_community_nodes(communities, target_community) do
    communities
    |> Enum.with_index()
    |> Enum.filter(fn {community, _idx} -> community == target_community end)
    |> Enum.map(fn {_community, idx} -> idx end)
  end

  @doc """
  Create hierarchical community structure.

  Builds a tree-like structure showing how communities are nested
  across different levels of the hierarchy.
  """
  @spec build_hierarchy(list(list()), list(map())) :: map()
  def build_hierarchy(all_level_communities, all_mappings) do
    levels = length(all_level_communities)

    hierarchy = %{
      levels: levels,
      communities_per_level: all_level_communities |> Enum.map(&length(Enum.uniq(&1))),
      level_mappings: all_mappings
    }

    # Build parent-child relationships
    parent_child_map = build_parent_child_relationships(all_level_communities, all_mappings)

    Map.put(hierarchy, :relationships, parent_child_map)
  end

  defp build_parent_child_relationships(all_level_communities, all_mappings)
       when length(all_level_communities) <= 1 do
    %{}
  end

  defp build_parent_child_relationships([current_level | remaining_levels], [
         current_mapping | remaining_mappings
       ]) do
    if length(remaining_levels) == 0 do
      %{}
    else
      next_level = hd(remaining_levels)
      next_mapping = hd(remaining_mappings)

      # Build relationships between current and next level
      current_relationships =
        build_level_relationships(current_level, next_level, current_mapping, next_mapping)

      # Recursively build relationships for remaining levels
      remaining_relationships =
        build_parent_child_relationships(remaining_levels, remaining_mappings)

      Map.merge(current_relationships, remaining_relationships)
    end
  end

  defp build_level_relationships(current_level, next_level, current_mapping, next_mapping) do
    # This is a simplified implementation
    # In practice, you'd track how communities at one level map to communities at the next level
    %{
      "level_#{length(current_level)}_to_#{length(next_level)}" => %{
        current: Enum.uniq(current_level) |> length(),
        next: Enum.uniq(next_level) |> length(),
        mapping: "communities aggregated"
      }
    }
  end
end
