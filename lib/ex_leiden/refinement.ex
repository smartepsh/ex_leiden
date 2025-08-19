defmodule ExLeiden.Refinement do
  @moduledoc """
  Refinement phase of the Leiden algorithm.

  This phase ensures that communities are well-connected by splitting
  disconnected communities into separate components. This is the key
  innovation that distinguishes Leiden from Louvain algorithm.
  """

  @doc """
  Perform the refinement phase.

  Checks each community for connectivity and splits disconnected
  communities into well-connected components.

  Returns updated community assignments where each community
  is guaranteed to be connected.
  """
  @spec refine_communities(Nx.Tensor.t(), list()) :: list()
  def refine_communities(adjacency_matrix, communities) do
    unique_communities = communities |> Enum.uniq() |> Enum.sort()

    # Process each community and split if disconnected
    {refined_communities, _next_community_id} =
      Enum.reduce(
        unique_communities,
        {communities, max_community_id(communities) + 1},
        fn community, {curr_communities, next_id} ->
          split_community_if_needed(adjacency_matrix, curr_communities, community, next_id)
        end
      )

    refined_communities
  end

  @doc """
  Check if a community is well-connected.

  A community is well-connected if there exists a path between
  any two nodes within the community using only edges within the community.
  """
  @spec community_connected?(Nx.Tensor.t(), list(), any()) :: boolean()
  def community_connected?(adjacency_matrix, communities, target_community) do
    community_nodes = get_community_nodes(communities, target_community)

    case length(community_nodes) do
      # Empty community is trivially connected
      0 -> true
      # Single node is trivially connected
      1 -> true
      _ -> check_connectivity(adjacency_matrix, community_nodes)
    end
  end

  @doc """
  Split a disconnected community into connected components.

  Returns a list of node lists, where each list represents
  a connected component of the original community.
  """
  @spec split_disconnected_community(Nx.Tensor.t(), list(), any()) :: list(list())
  def split_disconnected_community(adjacency_matrix, communities, target_community) do
    community_nodes = get_community_nodes(communities, target_community)

    if length(community_nodes) <= 1 do
      # Single node or empty - already connected
      [community_nodes]
    else
      find_connected_components(adjacency_matrix, community_nodes)
    end
  end

  # Private helper functions

  defp split_community_if_needed(adjacency_matrix, communities, target_community, next_id) do
    if community_connected?(adjacency_matrix, communities, target_community) do
      # Community is already connected, no split needed
      {communities, next_id}
    else
      # Split the community into connected components
      components = split_disconnected_community(adjacency_matrix, communities, target_community)

      case components do
        [_single_component] ->
          # Only one component found, shouldn't happen but handle gracefully
          {communities, next_id}

        multiple_components ->
          # Assign new community IDs to split components
          updated_communities =
            assign_split_communities(communities, target_community, multiple_components, next_id)

          new_next_id = next_id + length(multiple_components) - 1
          {updated_communities, new_next_id}
      end
    end
  end

  defp get_community_nodes(communities, target_community) do
    communities
    |> Enum.with_index()
    |> Enum.filter(fn {community, _idx} -> community == target_community end)
    |> Enum.map(fn {_community, idx} -> idx end)
  end

  defp max_community_id(communities) do
    case Enum.max(communities) do
      nil ->
        -1

      max_id when is_integer(max_id) ->
        max_id

      max_id ->
        # Handle non-integer community IDs by converting to hash
        :erlang.phash2(max_id)
    end
  end

  defp check_connectivity(adjacency_matrix, community_nodes) do
    if length(community_nodes) <= 1 do
      true
    else
      # Extract submatrix for the community
      indices = Nx.tensor(community_nodes)

      submatrix =
        adjacency_matrix
        |> Nx.take(indices, axis: 0)
        |> Nx.take(indices, axis: 1)

      # Use BFS to check if all nodes are reachable from the first node
      components = find_connected_components_from_matrix(submatrix)
      length(components) == 1
    end
  end

  defp find_connected_components(adjacency_matrix, community_nodes) do
    # Extract submatrix for the community
    indices = Nx.tensor(community_nodes)

    submatrix =
      adjacency_matrix
      |> Nx.take(indices, axis: 0)
      |> Nx.take(indices, axis: 1)

    # Find connected components in the submatrix
    components_indices = find_connected_components_from_matrix(submatrix)

    # Map back to original node indices
    components_indices
    |> Enum.map(fn component_indices ->
      Enum.map(component_indices, &Enum.at(community_nodes, &1))
    end)
  end

  defp find_connected_components_from_matrix(submatrix) do
    n = submatrix |> Nx.shape() |> elem(0)
    adjacency_list = matrix_to_adjacency_list(submatrix)

    # Use BFS to find all connected components
    visited = MapSet.new()
    components = []

    find_components_bfs(0, n, adjacency_list, visited, components)
  end

  defp find_components_bfs(current_node, n, adjacency_list, visited, components) do
    if current_node >= n do
      components
    else
      if MapSet.member?(visited, current_node) do
        find_components_bfs(current_node + 1, n, adjacency_list, visited, components)
      else
        # Start BFS from this unvisited node
        {component, new_visited} = bfs_component(current_node, adjacency_list, visited)

        find_components_bfs(current_node + 1, n, adjacency_list, new_visited, [
          component | components
        ])
      end
    end
  end

  defp bfs_component(start_node, adjacency_list, visited) do
    queue = :queue.new() |> :queue.in(start_node)
    component = []
    visited = MapSet.put(visited, start_node)

    bfs_traverse(queue, adjacency_list, visited, [start_node])
  end

  defp bfs_traverse(queue, adjacency_list, visited, component) do
    case :queue.out(queue) do
      {:empty, _queue} ->
        {component, visited}

      {{:value, node}, remaining_queue} ->
        neighbors = Map.get(adjacency_list, node, [])

        {new_queue, new_visited, new_component} =
          Enum.reduce(neighbors, {remaining_queue, visited, component}, fn neighbor, {q, v, c} ->
            if MapSet.member?(v, neighbor) do
              {q, v, c}
            else
              {
                :queue.in(neighbor, q),
                MapSet.put(v, neighbor),
                [neighbor | c]
              }
            end
          end)

        bfs_traverse(new_queue, adjacency_list, new_visited, new_component)
    end
  end

  defp matrix_to_adjacency_list(matrix) do
    n = matrix |> Nx.shape() |> elem(0)
    matrix_data = Nx.to_list(matrix)

    0..(n - 1)
    |> Enum.reduce(%{}, fn i, acc ->
      neighbors =
        matrix_data
        |> Enum.at(i)
        |> Enum.with_index()
        |> Enum.filter(fn {weight, _j} -> weight > 0 end)
        |> Enum.map(fn {_weight, j} -> j end)

      Map.put(acc, i, neighbors)
    end)
  end

  defp assign_split_communities(communities, original_community, components, next_id) do
    # Assign the first component to keep the original community ID
    # Assign new IDs to the remaining components
    [first_component | remaining_components] = components

    # Create mapping from node index to new community ID
    node_to_community = %{}

    # First component keeps original ID
    node_to_community =
      Enum.reduce(first_component, node_to_community, fn node_idx, acc ->
        Map.put(acc, node_idx, original_community)
      end)

    # Remaining components get new IDs
    {node_to_community, _final_next_id} =
      Enum.reduce(remaining_components, {node_to_community, next_id}, fn component,
                                                                         {mapping, current_id} ->
        updated_mapping =
          Enum.reduce(component, mapping, fn node_idx, acc ->
            Map.put(acc, node_idx, current_id)
          end)

        {updated_mapping, current_id + 1}
      end)

    # Apply the new community assignments
    communities
    |> Enum.with_index()
    |> Enum.map(fn {community, idx} ->
      if community == original_community do
        Map.get(node_to_community, idx, community)
      else
        community
      end
    end)
  end

  @doc """
  Get statistics about the refinement phase results.
  """
  @spec refinement_stats(list(), list()) :: map()
  def refinement_stats(initial_communities, refined_communities) do
    initial_count = initial_communities |> Enum.uniq() |> length()
    refined_count = refined_communities |> Enum.uniq() |> length()

    communities_split = refined_count - initial_count

    %{
      initial_communities: initial_count,
      refined_communities: refined_count,
      communities_split: communities_split,
      split_ratio: communities_split / max(initial_count, 1)
    }
  end
end
