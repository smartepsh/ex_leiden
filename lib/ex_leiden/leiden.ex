defmodule ExLeiden.Leiden do
  alias ExLeiden.Source
  require ExLeiden.Utils, as: Utils

  defmodule Behaviour do
    @type community_assignment :: %{id: integer(), children: [integer()]}
    @type bridge_connection :: %{community_a: integer(), community_b: integer(), weight: float()}
    @type level_results :: %{
            communities: [community_assignment()],
            bridges: [bridge_connection()]
          }

    @type results :: %{non_neg_integer() => level_results()}
    @callback call(Source.t(), keyword()) :: results()
  end

  @behaviour Behaviour
  @local_move_mod Utils.module(:local_move)
  @refine_partition_mod Utils.module(:refine_partition)
  @aggregate_mod Utils.module(:aggregate)

  @impl true
  def call(%Source{} = source, opts \\ []) do
    do_call(source, opts)
  end

  # Run Leiden algorithm across levels
  defp do_call(%Source{} = source, opts, current_level \\ 1, results \\ %{}) do
    max_level = Keyword.fetch!(opts, :max_level)

    if current_level > max_level do
      results
    else
      # Step 1: Local moving phase
      community_matrix_after_local = @local_move_mod.call(source, opts)

      # Check for convergence - if all communities are singletons, no more improvement possible
      if all_communities_are_singletons?(community_matrix_after_local) do
        results
      else
        # Step 2: Refinement phase
        refined_community_matrix =
          @refine_partition_mod.call(source.adjacency_matrix, community_matrix_after_local, opts)

        # Create communities for current level from refinement matrix
        current_communities = create_communities_from_refinement_matrix(refined_community_matrix)

        # Step 3: Aggregation phase - create new source for next level
        aggregated_source = @aggregate_mod.call(source.adjacency_matrix, refined_community_matrix)

        # Extract bridges from aggregated adjacency matrix
        current_bridges =
          extract_bridges_from_aggregated_matrix(aggregated_source.adjacency_matrix)

        # Add current level results (communities and bridges)
        level_results = %{communities: current_communities, bridges: current_bridges}
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
      # Get node indices that belong to this community
      member_node_indices =
        refinement_matrix[[.., community_idx]]
        |> Nx.equal(1)
        |> Nx.to_list()
        |> Enum.with_index()
        |> Enum.filter(fn {is_member, _idx} -> is_member == 1 end)
        |> Enum.map(fn {_is_member, node_idx} -> node_idx end)

      %{
        id: community_idx,
        children: member_node_indices
      }
    end)
  end

  # Extract bridge connections from aggregated adjacency matrix
  defp extract_bridges_from_aggregated_matrix(aggregated_matrix) do
    {n_communities, _} = Nx.shape(aggregated_matrix)

    if n_communities <= 1 do
      []
    else
      # Create upper triangular mask
      upper_tri_mask =
        Nx.iota({n_communities, n_communities}, axis: 1)
        |> Nx.greater(Nx.iota({n_communities, n_communities}, axis: 0))

      # Filter matrix: get upper triangle AND non-zero elements
      non_zero_mask = Nx.greater(aggregated_matrix, 0)
      bridge_mask = Nx.logical_and(upper_tri_mask, non_zero_mask)

      # Apply combined mask - only keep non-zero upper triangle elements
      filtered_matrix = Nx.select(bridge_mask, aggregated_matrix, 0)

      # Now enumerate only the elements that survived the filtering
      filtered_matrix
      |> Nx.to_list()
      |> Enum.with_index()
      |> Enum.flat_map(fn {row, i} ->
        row
        |> Enum.with_index()
        |> Enum.filter(fn {weight, _j} -> weight > 0 end)
        |> Enum.map(fn {weight, j} ->
          %{community_a: i, community_b: j, weight: weight}
        end)
      end)
    end
  end

  # Check if all communities are singletons (size 1) - means no beneficial merges found
  defp all_communities_are_singletons?(community_matrix) do
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
    |> Nx.to_number() == 1
  end
end
