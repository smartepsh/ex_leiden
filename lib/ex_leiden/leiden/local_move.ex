defmodule ExLeiden.Leiden.LocalMove do
  import Nx.Defn

  @moduledoc """
  Local moving phase implementation for the Leiden algorithm.

  This module implements the "MoveNodesFast" algorithm from the paper using a
  hybrid queue-based approach with matrix-optimized single-node calculations.

  ## Algorithm Overview

  1. Initialize queue with all nodes (shuffled for randomness)
  2. For each node in queue:
     - Use matrix operations to find best community move
     - If beneficial move found, apply it immediately
     - Add neighbors of moved node back to queue
  3. Repeat until queue is empty (convergence)

  This approach combines the paper's exact sequential processing with
  vectorized calculations for efficiency.
  """

  alias ExLeiden.Source

  alias ExLeiden.Utils

  defmodule Behaviour do
    @callback call(Source.t(), opts :: keyword()) :: Nx.Tensor.t()
  end

  @behaviour Behaviour

  @doc """
  Perform the local moving phase on a graph using queue-based node processing.

  This implements the core "MoveNodesFast" algorithm from the Leiden paper:
  - Sequential node processing with dynamic queue management
  - Matrix-optimized delta calculations for single nodes
  - Immediate partition updates after each beneficial move
  - Neighbor invalidation and re-queuing for locality

  ## Parameters

    - `source` - Source struct containing adjacency matrix and metadata
    - `opts` - Options including:
      - `:quality_function` - Quality function module (default: Modularity)
      - `:resolution` - Resolution parameter γ (default: 1.0)

  ## Returns

    Community matrix (Nx.Tensor) with optimized community assignments

  ## Examples

      iex> source = ExLeiden.Source.build!([[0, 1, 1], [1, 0, 0], [1, 0, 0]])
      iex> result = ExLeiden.Leiden.LocalMove.call(source, quality_function: :modularity, resolution: 1.0)
      iex> # Returns community matrix with optimized community assignments

  """
  @impl true
  def call(%Source{adjacency_matrix: matrix}, opts \\ []) do
    total_edges = matrix |> Nx.sum() |> Nx.divide(2) |> Nx.to_number()
    node_count = Nx.axis_size(matrix, 0)
    init_queue = create_shuffled_queue(node_count)
    init_community_matrix = Nx.eye(node_count)

    do_call(init_queue, matrix, init_community_matrix, total_edges, opts)
  end

  defp do_call(queue, matrix, community_matrix, total_edges, opts) do
    case next_value(queue) do
      {nil, _} ->
        community_matrix

      {current_node, new_queue} ->
        {best_community, delta_q} =
          quality_module(opts).best_move(
            matrix,
            current_node,
            community_matrix,
            total_edges,
            opts
          )

        if delta_q > 0 do
          new_community_matrix =
            new_community_matrix(community_matrix, current_node, best_community)

          not_visited_nodes = not_visited_nodes(matrix, current_node, new_community_matrix)

          # find can not visited nodes in community_matrix of current_node
          # push those nodes into queue
          new_queue = push_not_visited_nodes(new_queue, not_visited_nodes)

          do_call(new_queue, matrix, new_community_matrix, total_edges, opts)
        else
          do_call(new_queue, matrix, community_matrix, total_edges, opts)
        end
    end
  end

  defp new_community_matrix(community_matrix, current_node, best_community) do
    # Find current community and update both positions in one operation
    current_community = Nx.argmax(community_matrix[current_node]) |> Nx.to_number()

    # Create tensors outside defn
    indices = Nx.tensor([[current_node, current_community], [current_node, best_community]])
    values = Nx.tensor([0, 1])

    update_community_assignment(community_matrix, indices, values)
  end

  defnp update_community_assignment(community_matrix, indices, values) do
    Nx.indexed_put(community_matrix, indices, values)
  end

  defp next_value(queue) do
    case :queue.out(queue) do
      {{:value, value}, new_queue} -> {value, new_queue}
      {:empty, queue} -> {nil, queue}
    end
  end

  defp not_visited_nodes(matrix, current_node, community_matrix) do
    # Find current node's new community
    target_community = Nx.argmax(community_matrix[current_node]) |> Nx.to_number()

    result = find_candidate_nodes(matrix, current_node, community_matrix, target_community)

    # Extract indices where mask is true
    result
    |> Nx.to_flat_list()
    |> Enum.filter(fn idx -> idx >= 0 end)
  end

  defnp find_candidate_nodes(matrix, current_node, community_matrix, target_community) do
    # Get nodes in target community (column vector)
    target_community_nodes = community_matrix[[.., target_community]]

    # Get neighbors of current node (row vector)
    current_node_edges = matrix[current_node]

    # Find nodes that are both in target community AND connected to current node
    # Element-wise multiplication: 1 if both conditions true, 0 otherwise
    candidates = Nx.multiply(target_community_nodes, current_node_edges)

    # Find indices where candidates > 0 using matrix operations
    indices = Nx.iota({Nx.size(candidates)})
    mask = Nx.greater(candidates, 0)

    # Return indices with -1 for non-candidates
    Nx.select(mask, indices, -1)
  end

  # Queue management functions

  # Create shuffled queue of nodes for randomized processing order
  defp create_shuffled_queue(node_count) do
    0
    |> Range.new(node_count - 1)
    |> Enum.to_list()
    |> Enum.shuffle()
    |> :queue.from_list()
  end

  defp quality_module(opts) do
    case Keyword.fetch!(opts, :quality_function) do
      :modularity -> Utils.module(:modularity_quality)
      :cpm -> Utils.module(:cpm_quality)
    end
  end

  def push_not_visited_nodes(queue, []), do: queue

  def push_not_visited_nodes(queue, new_nodes) do
    new_values = :queue.from_list(new_nodes)
    :queue.join(queue, new_values)
  end
end
