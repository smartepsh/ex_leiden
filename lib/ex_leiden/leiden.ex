defmodule ExLeiden.Leiden do
  import Nx.Defn
  alias ExLeiden.Source
  alias ExLeiden.Utils

  defmodule Behaviour do
    @type community_assignment :: %{id: integer(), children: [integer()]}
    @type bridge_connection ::
            {community_a :: integer(), community_b :: integer(), weight :: number()}
    @type level_results :: {[community_assignment()], [bridge_connection()]}
    @type results :: %{non_neg_integer() => level_results()}
    @callback call(Source.t(), keyword()) :: results()
  end

  @behaviour Behaviour

  @impl true
  def call(%Source{} = source, opts \\ []) do
    do_call(source, opts)
  end

  # Run Leiden algorithm across levels
  defp do_call(%Source{} = source, opts, current_level \\ 1, results \\ %{}) do
    cond do
      # Check community size threshold first (takes precedence over max_level)
      should_terminate_by_community_size?(source, opts) ->
        results

      # Then check max_level
      should_terminate_by_max_level?(current_level, opts) ->
        results

      true ->
        # Step 1: Local moving phase
        community_matrix_after_local = Utils.module(:local_move).call(source, opts)

        # Check for convergence - if all communities are singletons, no more improvement possible
        if all_communities_are_singletons?(community_matrix_after_local) do
          results
        else
          # Step 2: Refinement phase
          refined_community_matrix =
            Utils.module(:refine_partition).call(
              source.adjacency_matrix,
              community_matrix_after_local,
              opts
            )

          # Create communities for current level from refinement matrix
          current_communities =
            create_communities_from_refinement_matrix(refined_community_matrix)

          # Step 3: Aggregation phase - create new source for next level
          aggregated_source =
            Utils.module(:aggregate).call(source.adjacency_matrix, refined_community_matrix)

          # Extract bridges from aggregated adjacency matrix
          current_bridges =
            extract_bridges_from_aggregated_matrix(aggregated_source.adjacency_matrix)

          # Add current level results (communities and bridges)
          level_results = {current_communities, current_bridges}
          updated_results = Map.put(results, current_level, level_results)

          # Continue to next level with aggregated source
          do_call(aggregated_source, opts, current_level + 1, updated_results)
        end
    end
  end

  # Create communities directly from refinement matrix
  defp create_communities_from_refinement_matrix(refinement_matrix) do
    {_n_nodes, n_communities} = Nx.shape(refinement_matrix)

    Enum.map(0..(n_communities - 1), fn community_idx ->
      # Get node indices that belong to this community using GPU
      member_mask = get_community_member_mask(refinement_matrix, community_idx)

      member_node_indices =
        member_mask
        |> Nx.to_flat_list()
        |> Enum.with_index()
        |> Enum.filter(fn {is_member, _idx} -> is_member == 1 end)
        |> Enum.map(fn {_is_member, node_idx} -> node_idx end)

      %{
        id: community_idx,
        children: member_node_indices
      }
    end)
  end

  defnp get_community_member_mask(refinement_matrix, community_idx) do
    refinement_matrix[[.., community_idx]]
    |> Nx.equal(1)
  end

  # Extract bridge connections from aggregated adjacency matrix
  defp extract_bridges_from_aggregated_matrix(aggregated_matrix) do
    {n_communities, _} = Nx.shape(aggregated_matrix)

    if n_communities <= 1 do
      []
    else
      extract_upper_triangular_nonzero(aggregated_matrix)
    end
  end

  # GPU-accelerated extraction of upper triangular non-zero elements
  defp extract_upper_triangular_nonzero(matrix) do
    filtered_matrix = create_filtered_bridge_matrix(matrix)

    # Convert to Elixir list structure (CPU transfer only at the end)
    filtered_matrix
    |> Nx.to_list()
    |> Enum.with_index()
    |> Enum.flat_map(fn {row, i} ->
      row
      |> Enum.with_index()
      |> Enum.filter(fn {weight, _j} -> weight > 0 end)
      |> Enum.map(fn {weight, j} ->
        {i, j, weight}
      end)
    end)
  end

  # Create filtered matrix with only upper triangular non-zero elements
  defnp create_filtered_bridge_matrix(aggregated_matrix) do
    {n_communities, _} = Nx.shape(aggregated_matrix)

    # Create upper triangular mask
    upper_tri_mask =
      Nx.iota({n_communities, n_communities}, axis: 1)
      |> Nx.greater(Nx.iota({n_communities, n_communities}, axis: 0))

    # Filter matrix: get upper triangle AND non-zero elements
    non_zero_mask = Nx.greater(aggregated_matrix, 0)
    bridge_mask = Nx.logical_and(upper_tri_mask, non_zero_mask)

    # Apply combined mask - only keep non-zero upper triangle elements
    Nx.select(bridge_mask, aggregated_matrix, 0)
  end

  # Check if should terminate based on community size threshold
  defp should_terminate_by_community_size?(%Source{adjacency_matrix: adj_matrix}, opts) do
    community_size_threshold = Keyword.fetch!(opts, :community_size_threshold)

    case community_size_threshold do
      nil ->
        false

      threshold when is_integer(threshold) ->
        # Community size is the number of nodes in each community (the matrix dimensions)
        {n_communities, _} = Nx.shape(adj_matrix)

        # If we have communities at or below the threshold, terminate
        n_communities <= threshold
    end
  end

  # Check if should terminate based on max_level
  defp should_terminate_by_max_level?(current_level, opts) do
    max_level = Keyword.fetch!(opts, :max_level)
    current_level > max_level
  end

  # Check if all communities are singletons (size 1) - means no beneficial merges found
  defp all_communities_are_singletons?(community_matrix) do
    result = check_all_singletons(community_matrix)
    Nx.to_number(result) == 1
  end

  defnp check_all_singletons(community_matrix) do
    # Calculate size of each community (sum of each column)
    community_sizes = Nx.sum(community_matrix, axes: [0])

    # Check if all non-empty communities have size 1
    community_sizes
    # Mask for existing communities
    |> Nx.greater(0)
    # Keep only existing community sizes
    |> Nx.select(community_sizes, 0)
    # Check if all are size 1
    |> Nx.equal(1)
    # All must be true
    |> Nx.all()
  end
end
