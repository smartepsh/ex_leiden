defmodule ExLeiden.Algorithm do
  @moduledoc """
  Main Leiden algorithm implementation.

  Orchestrates the three phases of the Leiden algorithm:
  1. Local moving phase
  2. Refinement phase
  3. Aggregation phase

  The algorithm runs iteratively until convergence or maximum levels reached.
  """

  alias ExLeiden.{Source, LocalMoving, Refinement, Aggregation, Quality}

  @doc """
  Run the complete Leiden algorithm.

  Takes a Source struct and opts, returns hierarchical community structure.
  """
  def run(
        %Source{adjacency_matrix: adj_matrix, degree_sequence: degrees},
        opts
      ) do
    quality_function = opts.quality_function
    gamma = opts.resolution
    max_level = opts.max_level
    format = opts.format

    # Initialize: each node in its own community
    n_nodes = length(degrees)
    initial_communities = 0..(n_nodes - 1) |> Enum.to_list()

    # Run iterative Leiden phases
    results =
      run_leiden_phases(
        adj_matrix,
        initial_communities,
        quality_function,
        gamma,
        max_level,
        0,
        # Accumulator for all levels
        []
      )

    # Format results according to requested format
    format_results(results, format, opts)
  end

  defp run_leiden_phases(
         adj_matrix,
         communities,
         quality_function,
         gamma,
         max_level,
         current_level,
         level_results
       ) do
    if current_level >= max_level do
      # Maximum level reached, return accumulated results
      Enum.reverse([{current_level - 1, adj_matrix, communities} | level_results])
    else
      # Phase 1: Local Moving
      communities_after_local =
        LocalMoving.local_moving_phase(
          adj_matrix,
          communities,
          quality_function,
          gamma
        )

      # Phase 2: Refinement
      communities_after_refinement =
        Refinement.refine_communities(
          adj_matrix,
          communities_after_local
        )

      # Check for convergence (no changes in communities)
      if communities_converged?(communities, communities_after_refinement) do
        # Converged, return results
        Enum.reverse([{current_level, adj_matrix, communities_after_refinement} | level_results])
      else
        # Phase 3: Aggregation
        {aggregate_matrix, community_mapping} =
          Aggregation.aggregate_network(
            adj_matrix,
            communities_after_refinement
          )

        # Check if we should continue aggregation
        if Aggregation.should_continue_aggregation?(community_mapping, current_level, max_level) do
          # Initialize communities for next level
          next_level_communities = Aggregation.initial_aggregate_communities(community_mapping)

          # Store current level results and continue
          current_level_result =
            {current_level, adj_matrix, communities_after_refinement, community_mapping}

          run_leiden_phases(
            aggregate_matrix,
            next_level_communities,
            quality_function,
            gamma,
            max_level,
            current_level + 1,
            [current_level_result | level_results]
          )
        else
          # Stop aggregation, return results
          Enum.reverse([
            {current_level, adj_matrix, communities_after_refinement} | level_results
          ])
        end
      end
    end
  end

  defp communities_converged?(prev_communities, curr_communities) do
    # Check if community assignments are the same (accounting for community ID changes)
    normalized_prev = normalize_community_ids(prev_communities)
    normalized_curr = normalize_community_ids(curr_communities)

    normalized_prev == normalized_curr
  end

  defp normalize_community_ids(communities) do
    # Map community IDs to sequential integers starting from 0
    unique_communities = communities |> Enum.uniq() |> Enum.sort()
    id_mapping = unique_communities |> Enum.with_index() |> Map.new()

    Enum.map(communities, &Map.get(id_mapping, &1))
  end

  # Result formatting

  defp format_results(level_results, format, opts) do
    case format do
      :communities_and_bridges -> format_communities_and_bridges(level_results, opts)
      :graph -> format_graph_results(level_results, opts)
      :raw -> format_raw_results(level_results, opts)
    end
  end

  defp format_communities_and_bridges(level_results, _opts) do
    level_results
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {level_data, _idx}, acc ->
      {level, matrix, communities} =
        case level_data do
          {l, m, c, _mapping} -> {l, m, c}
          {l, m, c} -> {l, m, c}
        end

      level_info = %{
        communities: build_communities_map(communities, level),
        bridges: build_bridges_list(matrix, communities, level)
      }

      Map.put(acc, level, level_info)
    end)
    |> add_algorithm_stats(level_results)
  end

  defp format_graph_results(level_results, _opts) do
    # This would integrate with libgraph to create Graph structs
    # For now, return a simplified format
    level_results
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {level_data, _idx}, acc ->
      {level, matrix, communities} =
        case level_data do
          {l, m, c, _mapping} -> {l, m, c}
          {l, m, c} -> {l, m, c}
        end

      level_info = %{
        adjacency_matrix: matrix,
        communities: communities,
        nodes: length(communities),
        edges: (matrix |> Nx.sum() |> Nx.to_number()) / 2
      }

      Map.put(acc, level, level_info)
    end)
  end

  defp format_raw_results(level_results, _opts) do
    %{
      levels: length(level_results),
      results: level_results,
      algorithm: "leiden"
    }
  end

  defp build_communities_map(communities, level) do
    communities
    |> Enum.with_index()
    |> Enum.group_by(fn {community, _node_idx} -> community end, fn {_community, node_idx} ->
      node_idx
    end)
    |> Enum.into(%{}, fn {community, nodes} ->
      {{level, community}, nodes}
    end)
  end

  defp build_bridges_list(matrix, communities, level) do
    unique_communities = communities |> Enum.uniq() |> Enum.sort()

    # Calculate weights between all pairs of communities
    for c1 <- unique_communities,
        c2 <- unique_communities,
        # Only consider each pair once
        c1 < c2 do
      weight = Aggregation.inter_community_weight(matrix, communities, c1, c2)

      if weight > 0 do
        {{level, c1}, {level, c2}, weight}
      else
        nil
      end
    end
    |> Enum.filter(&(&1 != nil))
  end

  defp add_algorithm_stats(formatted_results, level_results) do
    stats = %{
      total_levels: length(level_results),
      convergence_info: analyze_convergence(level_results),
      quality_progression: calculate_quality_progression(level_results)
    }

    Map.put(formatted_results, :algorithm_stats, stats)
  end

  defp analyze_convergence(level_results) do
    %{
      # More than one level indicates non-trivial convergence
      converged: length(level_results) > 1,
      final_communities: level_results |> List.last() |> elem(2) |> Enum.uniq() |> length(),
      levels_processed: length(level_results)
    }
  end

  defp calculate_quality_progression(level_results) do
    # Calculate quality at each level (simplified)
    level_results
    |> Enum.map(fn level_data ->
      {level, matrix, communities} =
        case level_data do
          {l, m, c, _mapping} -> {l, m, c}
          {l, m, c} -> {l, m, c}
        end

      quality = Quality.modularity(matrix, communities, 1.0)
      {level, quality}
    end)
  end
end
