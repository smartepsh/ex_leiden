defmodule ExLeiden.Leiden.RefinePartition do
  import Nx.Defn
  alias ExLeiden.Utils

  defmodule Behaviour do
    @callback call(Nx.Tensor.t(), Nx.Tensor.t(), keyword()) :: Nx.Tensor.t()
  end

  @behaviour Behaviour
  @moduledoc """
  Implements the refinement phase of the Leiden algorithm.

  The refinement phase ensures that communities are well-connected by:
  1. Starting with a singleton partition where each node is in its own community
  2. Locally merging nodes within each original community
  3. Only merging nodes that are sufficiently well connected to their community
  4. Using randomization to explore the partition space more broadly

  This phase is crucial for guaranteeing well-connected communities, which is
  the main advantage of Leiden over Louvain algorithm.
  """

  @doc """
  Refine a partition to ensure well-connected communities.

  ## Parameters

  - `adjacency_matrix` - The adjacency matrix of the graph (n x n tensor)
  - `community_matrix` - Current community assignment matrix (n x c binary matrix)
  - `opts` - Options including:
    - `:resolution` - Resolution parameter (default: 1.0)
    - `:theta` - Randomness parameter for community selection (default: 0.01)
    - `:quality_function` - Quality function to use (:modularity or :cpm, default: :modularity)
    - `:select_best_for_test` - If true, always select the best community instead of randomized selection (default: false)

  ## Returns

  A new community matrix representing the refined partition where each
  community from the original partition may be split into multiple
  well-connected subcommunities.

  ## Examples

      iex> adjacency = Nx.tensor([[0, 1, 1], [1, 0, 0], [1, 0, 0]])
      iex> community_matrix = Nx.tensor([[1, 0], [1, 0], [0, 1]])
      iex> refined = ExLeiden.Leiden.RefinePartition.call(adjacency, community_matrix)

  """
  @impl true
  def call(adjacency_matrix, community_matrix, opts) do
    {n_nodes, n_communities} = Nx.shape(community_matrix)

    # 1. Map: Process each community independently, preserving subset information
    refined_communities_with_subsets =
      Range.new(0, n_communities - 1)
      |> Enum.reduce([], fn community_idx, acc ->
        case get_community_nodes(community_matrix, community_idx) do
          [] ->
            acc

          [single_node] ->
            # Single node community - no refinement needed
            [{[single_node], Nx.tensor([[1]])} | acc]

          subset ->
            # Multi-node community - refine it
            subset_matrix = get_subset_matrix(adjacency_matrix, subset)
            refined_partition = execute_individual_moves(subset_matrix, opts)

            [{subset, refined_partition} | acc]
        end
      end)
      |> Enum.reverse()

    # 2. Calculate total communities needed
    total_communities =
      refined_communities_with_subsets
      |> Enum.map(fn {_subset, local_partition} ->
        {_, n_local_communities} = Nx.shape(local_partition)
        n_local_communities
      end)
      |> Enum.sum()

    # 3. Build final matrix with correct size
    final_partition = Nx.broadcast(0, {n_nodes, total_communities})

    # 4. Use Nx.index_add to build final matrix maintaining original node order
    full_partition =
      build_final_partition_with_subset_mapping(final_partition, refined_communities_with_subsets)

    # 5. Remove empty communities (columns that are all zeros)
    remove_empty_communities(full_partition)
  end

  # Get list of node indices belonging to a community
  defp get_community_nodes(community_matrix, community_idx) do
    community_column = extract_community_column(community_matrix, community_idx)
    community_size = Nx.sum(community_column) |> Nx.to_number()

    # Handle empty communities
    if community_size == 0 do
      []
    else
      community_column
      |> Nx.argsort(direction: :desc)
      |> Nx.slice([0], [community_size])
      |> Nx.to_flat_list()
    end
  end

  defnp extract_community_column(community_matrix, community_idx) do
    community_matrix
    |> Nx.slice_along_axis(community_idx, 1, axis: 1)
    |> Nx.squeeze(axes: [1])
  end

  # Calculate sub-matrices for each community using Stream for memory efficiency
  defp get_subset_matrix(adjacency_matrix, community_nodes) do
    # Convert list to tensor for Nx operations (outside defn)
    indices = Nx.tensor(community_nodes)

    # Extract submatrix using defn
    extract_submatrix(adjacency_matrix, indices)
  end

  defnp extract_submatrix(adjacency_matrix, indices) do
    # Extract submatrix by taking rows and columns for the subset nodes
    adjacency_matrix
    # Take rows for subset nodes
    |> Nx.take(indices, axis: 0)
    # Take columns for subset nodes
    |> Nx.take(indices, axis: 1)
  end

  # Calculate well-connected communities mask based on γ-connectivity using pure matrix operations
  # A community C is well-connected to subset S if: E(C, S - C) >= γ * ||C|| * ||S - C||
  defnp calculate_well_connected_communities_mask(
          subset_adjacency_matrix,
          partition_matrix,
          resolution,
          subset_size
        ) do
    # Calculate community sizes for all communities at once
    community_sizes = Nx.sum(partition_matrix, axes: [0])

    # Calculate edges from each community to outside using matrix operations
    # For each community C: E(C, S - C) = sum of edges from C to nodes in (S - C)

    # Step 1: Create community adjacency matrix (communities × nodes)
    # partition_matrix is (nodes × communities), transpose to get (communities × nodes)
    communities_nodes = Nx.transpose(partition_matrix)

    # Step 2: Calculate total edges from each community to all nodes
    # communities_nodes × subset_adjacency_matrix = (communities × nodes) × (nodes × nodes) = (communities × nodes)
    community_to_all_edges = Nx.dot(communities_nodes, subset_adjacency_matrix)

    # Step 3: Calculate edges from each community to itself (internal edges)
    # For community i: sum(community_to_all_edges[i] * communities_nodes[i])
    community_internal_edges =
      community_to_all_edges
      |> Nx.multiply(communities_nodes)
      |> Nx.sum(axes: [1])

    # Step 4: Calculate edges from each community to rest of subset S
    # E(C, S - C) = edges from C to (S - C) within the subset
    # community_to_all_edges already contains edges from each community to all nodes in subset S
    # Sum across all nodes gives total edges from community to all nodes in subset S
    community_to_subset_edges = Nx.sum(community_to_all_edges, axes: [1])

    # E(C, S - C) = edges from C to all nodes in S minus internal edges within C
    community_external_edges = Nx.subtract(community_to_subset_edges, community_internal_edges)

    # Step 5: Calculate connectivity thresholds for all communities
    # γ * ||C|| * ||S - C|| for each community C
    rest_of_subset_sizes = Nx.subtract(subset_size, community_sizes)

    connectivity_thresholds =
      community_sizes
      |> Nx.multiply(rest_of_subset_sizes)
      |> Nx.multiply(resolution)

    # Step 6: Check γ-connectivity condition for all communities at once
    # E(C, S - C) >= γ * ||C|| * ||S - C||
    well_connected_mask = Nx.greater_equal(community_external_edges, connectivity_thresholds)

    # Step 7: Handle empty communities (size 0) - they are not well-connected
    non_empty_mask = Nx.greater(community_sizes, 0)

    # Final mask: well-connected AND non-empty
    Nx.logical_and(well_connected_mask, non_empty_mask)
  end

  # Select community using randomized selection weighted by exp(gain/theta) or deterministic best selection
  # Takes a gains matrix where non-negative values are valid candidates, negative are invalid
  defp select_community_with_theta(filtered_gains, opts) do
    # Create mask for valid candidates (positive or zero gains)
    valid_mask = create_valid_mask(filtered_gains)

    # Count number of valid candidates
    num_valid = Nx.sum(valid_mask) |> Nx.to_number()

    if num_valid == 0 do
      nil
    else
      if Keyword.get(opts, :select_best_for_test, false) do
        # Deterministic mode: select community with highest gain
        # Set invalid candidates to very negative value
        filtered_gains |> Nx.argmax() |> Nx.to_number()
      else
        # Randomized mode: original theta-based selection
        theta = Keyword.fetch!(opts, :theta)

        # Calculate probabilities using defn
        probabilities = calculate_theta_probabilities(filtered_gains, valid_mask, theta)

        # Generate random value and find selection using cumulative probability
        random_val = :rand.uniform()

        # Calculate cumulative probabilities and find selection
        selection_idx = find_random_selection(probabilities, random_val)
        Nx.to_number(selection_idx)
      end
    end
  end

  defnp create_valid_mask(filtered_gains) do
    Nx.greater_equal(filtered_gains, 0)
  end

  defnp calculate_theta_probabilities(filtered_gains, valid_mask, theta) do
    # Extract only valid gains for probability calculation
    valid_gains = Nx.select(valid_mask, filtered_gains, 0)

    # Calculate weights using matrix operations: exp(gain/theta) for valid gains only
    weights =
      valid_gains
      |> Nx.divide(theta)
      |> Nx.exp()
      # Zero out invalid positions
      |> Nx.multiply(Nx.select(valid_mask, 1.0, 0.0))

    total_weight = Nx.sum(weights)

    # Calculate probabilities
    Nx.divide(weights, total_weight)
  end

  defnp find_random_selection(probabilities, random_val) do
    # Calculate cumulative probabilities
    cumulative_probs = Nx.cumulative_sum(probabilities, axis: 0)

    # Find first index where cumulative probability >= random_val
    selection_mask = Nx.greater_equal(cumulative_probs, random_val)
    # Return the selected community index
    Nx.argmax(selection_mask)
  end

  # Build final partition matrix using subset mappings and single Nx.indexed_add
  defp build_final_partition_with_subset_mapping(
         final_partition,
         refined_communities_with_subsets
       ) do
    # Collect all indices and values using direct subset-to-global mapping
    {all_indices, all_values} =
      collect_indices_and_values_from_subsets(refined_communities_with_subsets)

    if length(all_indices) == 0 do
      final_partition
    else
      # Single indexed_add call with all indices and values
      indices_tensor = Nx.tensor(all_indices)
      values_tensor = Nx.tensor(all_values)
      Nx.indexed_add(final_partition, indices_tensor, values_tensor)
    end
  end

  # Collect indices and values using direct subset-to-global mapping
  defp collect_indices_and_values_from_subsets(refined_communities_with_subsets) do
    {_final_community_offset, all_indices, all_values} =
      refined_communities_with_subsets
      |> Enum.reduce({0, [], []}, fn {subset, local_partition},
                                     {community_offset, indices_acc, values_acc} ->
        # subset = [global_node_1, global_node_2, ...] (ordered node indices)
        # local_partition = tensor showing which local community each local node belongs to
        # community_offset = current global community offset (0, then 3, then 5, etc.)

        if length(subset) == 0 do
          {community_offset, indices_acc, values_acc}
        else
          {_, n_local_communities} = Nx.shape(local_partition)

          # For each node in subset (preserving order):
          {new_indices, new_values} =
            subset
            # [(global_node_1, 0), (global_node_2, 1), ...]
            |> Enum.with_index()
            |> Enum.reduce({[], []}, fn {global_node_idx, local_node_idx}, {idx_acc, val_acc} ->
              # Get which local community this node belongs to (0, 1, 2, ...)
              local_community_idx =
                local_partition[local_node_idx] |> Nx.argmax() |> Nx.to_number()

              # Convert to global community index
              global_community_idx = community_offset + local_community_idx

              # Add this assignment
              index = [global_node_idx, global_community_idx]
              {[index | idx_acc], [1 | val_acc]}
            end)

          # Update for next iteration
          next_community_offset = community_offset + n_local_communities
          {next_community_offset, new_indices ++ indices_acc, new_values ++ values_acc}
        end
      end)

    {Enum.reverse(all_indices), Enum.reverse(all_values)}
  end

  # Remove empty communities (columns that are all zeros) using matrix operations
  defp remove_empty_communities(partition_matrix) do
    # Calculate community sizes (sum of each column)
    community_sizes = calculate_community_sizes(partition_matrix)

    # Create mask for non-empty communities (size > 0)
    non_empty_mask = create_non_empty_mask(community_sizes)

    # Count non-empty communities
    n_non_empty = Nx.sum(non_empty_mask) |> Nx.to_number()

    # If all communities are non-empty, return original matrix
    {_, n_communities} = Nx.shape(partition_matrix)

    if n_non_empty == n_communities do
      partition_matrix
    else
      # Use boolean indexing to select only non-empty community columns
      # Create indices tensor for non-empty communities
      non_empty_indices =
        non_empty_mask
        |> Nx.argsort(direction: :desc)
        |> Nx.slice([0], [n_non_empty])

      # Take only the non-empty community columns
      take_non_empty_communities(partition_matrix, non_empty_indices)
    end
  end

  defnp calculate_community_sizes(partition_matrix) do
    Nx.sum(partition_matrix, axes: [0])
  end

  defnp create_non_empty_mask(community_sizes) do
    Nx.greater(community_sizes, 0)
  end

  defnp take_non_empty_communities(partition_matrix, non_empty_indices) do
    Nx.take(partition_matrix, non_empty_indices, axis: 1)
  end

  # Process refinement moves - one round iteration as per Algorithm A.2
  defp execute_individual_moves(subset_adjacency_matrix, opts) do
    {n_nodes, _} = Nx.shape(subset_adjacency_matrix)

    # Start with singleton partition - each node in its own community
    init_partition = Nx.eye(n_nodes)

    # Algorithm A.2: Single round iteration through all nodes
    # For each node in singleton community, try to merge with well-connected community
    Range.new(0, n_nodes - 1)
    |> Enum.reduce(init_partition, fn node_idx, partition_acc ->
      # Check if node is CURRENTLY in singleton community
      if is_node_in_singleton_community?(partition_acc, node_idx) do
        # Calculate well-connected communities once per partition state (Algorithm A.2 line 37)
        # T ← {C | C ∈ P, C ⊆ S, E(C, S - C) ≥ γ||C|| · ||S - C||}
        subset_size = Nx.axis_size(partition_acc, 0)

        well_connected_communities =
          calculate_well_connected_communities_mask(
            subset_adjacency_matrix,
            partition_acc,
            Keyword.fetch!(opts, :resolution),
            subset_size
          )

        # Calculate quality gains for all communities and filter by well-connectivity
        total_edges = Nx.sum(subset_adjacency_matrix) |> Nx.divide(2) |> Nx.to_number()

        all_quality_gains =
          calculate_quality_gains_for_node(
            subset_adjacency_matrix,
            node_idx,
            partition_acc,
            total_edges,
            opts
          )

        # Filter gains to only well-connected communities with non-negative gains
        filtered_gains =
          filter_gains_by_well_connectivity(all_quality_gains, well_connected_communities)

        # Find a community to merge with using theta-based selection on quality gains
        target_community = select_community_with_theta(filtered_gains, opts)

        if is_nil(target_community) do
          partition_acc
        else
          # Apply the merge immediately to update partition state
          apply_single_move(partition_acc, node_idx, target_community)
        end
      else
        partition_acc
      end
    end)
  end

  # Check if a node is currently in a singleton community
  defp is_node_in_singleton_community?(partition_matrix, node_idx) do
    result = check_singleton_community(partition_matrix, node_idx)
    Nx.to_number(result) == 1
  end

  defnp check_singleton_community(partition_matrix, node_idx) do
    # Get the community index of the node
    community_idx = Nx.argmax(partition_matrix[node_idx])

    # Calculate the size of that community and check if it's 1
    partition_matrix[[.., community_idx]]
    |> Nx.sum()
    |> Nx.equal(1)
  end

  # Apply a single move (merge node into target community)
  defp apply_single_move(partition_matrix, node_idx, target_community_idx) do
    current_community_idx = Nx.argmax(partition_matrix[node_idx]) |> Nx.to_number()

    # Create tensors outside defn
    updates = Nx.tensor([[node_idx, current_community_idx], [node_idx, target_community_idx]])
    values = Nx.tensor([0, 1])

    apply_move_update(partition_matrix, updates, values)
  end

  defnp apply_move_update(partition_matrix, updates, values) do
    Nx.indexed_put(partition_matrix, updates, values)
  end

  # Calculate quality gains for a specific node using the quality modules
  defp calculate_quality_gains_for_node(
         subset_adjacency_matrix,
         node_idx,
         partition_matrix,
         total_edges,
         opts
       ) do
    # Delegate to quality module functions
    module =
      case Keyword.fetch!(opts, :quality_function) do
        :cpm -> Utils.module(:cpm_quality)
        :modularity -> Utils.module(:modularity_quality)
      end

    resolution = Keyword.fetch!(opts, :resolution)

    module.delta_gains(
      subset_adjacency_matrix,
      node_idx,
      partition_matrix,
      total_edges,
      resolution
    )
  end

  # Filter quality gains to only include well-connected communities with non-negative gains
  defnp filter_gains_by_well_connectivity(all_quality_gains, well_connected_mask) do
    # Create mask for non-negative gains
    non_negative_gains_mask = Nx.greater_equal(all_quality_gains, 0)

    # Combine masks: must be well-connected AND have non-negative gains
    valid_candidates_mask = Nx.logical_and(well_connected_mask, non_negative_gains_mask)

    # Return gains for valid candidates, 0 for invalid ones
    valid_mask_as_float = Nx.select(valid_candidates_mask, 1.0, 0.0)
    Nx.multiply(all_quality_gains, valid_mask_as_float)
  end
end
