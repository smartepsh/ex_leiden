defmodule ExLeiden.LocalMoving do
  @moduledoc """
  Local moving phase of the Leiden algorithm.

  In this phase, nodes are moved between communities to optimize the quality function.
  The algorithm continues until no further improvements can be made.
  """

  alias ExLeiden.Quality

  @doc """
  Perform the local moving phase.

  Iteratively moves nodes between communities to optimize the quality function
  until no beneficial moves remain.

  Returns the updated community assignments.
  """
  @spec local_moving_phase(Nx.Tensor.t(), list(), atom(), number()) :: list()
  def local_moving_phase(
        adjacency_matrix,
        initial_communities,
        quality_function \\ :modularity,
        gamma \\ 1.0
      ) do
    n_nodes = length(initial_communities)

    # Start with initial communities
    iterate_until_stable(
      adjacency_matrix,
      initial_communities,
      quality_function,
      gamma,
      0,
      n_nodes
    )
  end

  # Main iteration loop
  defp iterate_until_stable(
         adjacency_matrix,
         communities,
         quality_function,
         gamma,
         iteration,
         max_iterations
       ) do
    if iteration >= max_iterations do
      # Prevent infinite loops
      communities
    else
      # Process nodes in random order for better convergence
      node_order = 0..(length(communities) - 1) |> Enum.to_list() |> Enum.shuffle()

      {new_communities, any_improvement} =
        Enum.reduce(node_order, {communities, false}, fn node_idx, {curr_communities, improved} ->
          # Find the best community for this node
          best_move =
            find_best_community_for_node(
              adjacency_matrix,
              curr_communities,
              node_idx,
              quality_function,
              gamma
            )

          case best_move do
            {:move, new_community, _gain} ->
              updated_communities = List.replace_at(curr_communities, node_idx, new_community)
              {updated_communities, true}

            :no_move ->
              {curr_communities, improved}
          end
        end)

      if any_improvement do
        # Continue if improvements were made
        iterate_until_stable(
          adjacency_matrix,
          new_communities,
          quality_function,
          gamma,
          iteration + 1,
          max_iterations
        )
      else
        # Converged
        new_communities
      end
    end
  end

  defp find_best_community_for_node(
         adjacency_matrix,
         communities,
         node_idx,
         quality_function,
         gamma
       ) do
    current_community = Enum.at(communities, node_idx)

    # Get neighboring communities (communities of adjacent nodes)
    neighboring_communities = get_neighboring_communities(adjacency_matrix, communities, node_idx)

    # Also consider staying in current community
    candidate_communities = [current_community | neighboring_communities] |> Enum.uniq()

    # Calculate quality gain for each possible move
    gains =
      candidate_communities
      |> Enum.map(fn target_community ->
        gain =
          if target_community == current_community do
            # No gain for staying
            0.0
          else
            Quality.quality_gain(
              quality_function,
              adjacency_matrix,
              communities,
              node_idx,
              current_community,
              target_community,
              gamma
            )
          end

        {target_community, gain}
      end)

    # Find the best gain
    {best_community, best_gain} = Enum.max_by(gains, fn {_community, gain} -> gain end)

    if best_gain > 0 and best_community != current_community do
      {:move, best_community, best_gain}
    else
      :no_move
    end
  end

  defp get_neighboring_communities(adjacency_matrix, communities, node_idx) do
    # Get the adjacency row for this node
    node_connections = Nx.take(adjacency_matrix, node_idx, axis: 0) |> Nx.to_list()

    # Find communities of connected nodes
    node_connections
    |> Enum.with_index()
    |> Enum.filter(fn {weight, _idx} -> weight > 0 end)
    |> Enum.map(fn {_weight, neighbor_idx} -> Enum.at(communities, neighbor_idx) end)
    |> Enum.uniq()
  end

  @doc """
  Vectorized version of local moving phase for better performance.

  Processes multiple nodes simultaneously using matrix operations.
  """
  @spec vectorized_local_moving_phase(Nx.Tensor.t(), list(), atom(), number()) :: list()
  def vectorized_local_moving_phase(
        adjacency_matrix,
        initial_communities,
        quality_function \\ :modularity,
        gamma \\ 1.0
      ) do
    # For now, fall back to standard implementation
    # TODO: Implement full vectorization when needed for performance
    local_moving_phase(adjacency_matrix, initial_communities, quality_function, gamma)
  end

  @doc """
  Calculate the total quality improvement from local moving phase.

  This can be used to determine if the phase was effective.
  """
  @spec quality_improvement(Nx.Tensor.t(), list(), list(), atom(), number()) :: number()
  def quality_improvement(
        adjacency_matrix,
        initial_communities,
        final_communities,
        quality_function,
        gamma
      ) do
    initial_quality = Quality.modularity(adjacency_matrix, initial_communities, gamma)
    final_quality = Quality.modularity(adjacency_matrix, final_communities, gamma)

    case quality_function do
      :modularity ->
        final_quality - initial_quality

      :cpm ->
        Quality.cpm(adjacency_matrix, final_communities, gamma) -
          Quality.cpm(adjacency_matrix, initial_communities, gamma)
    end
  end

  @doc """
  Check if communities have converged (no changes between iterations).
  """
  @spec converged?(list(), list()) :: boolean()
  def converged?(prev_communities, curr_communities) do
    prev_communities == curr_communities
  end

  @doc """
  Get statistics about the local moving phase results.
  """
  @spec moving_stats(list(), list()) :: map()
  def moving_stats(initial_communities, final_communities) do
    initial_community_count = initial_communities |> Enum.uniq() |> length()
    final_community_count = final_communities |> Enum.uniq() |> length()

    nodes_moved =
      initial_communities
      |> Enum.zip(final_communities)
      |> Enum.count(fn {initial, final} -> initial != final end)

    %{
      initial_communities: initial_community_count,
      final_communities: final_community_count,
      nodes_moved: nodes_moved,
      stability_ratio: 1.0 - nodes_moved / length(initial_communities)
    }
  end
end
