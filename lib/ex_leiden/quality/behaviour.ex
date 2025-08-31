defmodule ExLeiden.Quality.Behaviour do
  @moduledoc """
  Behaviour definition for quality functions in the Leiden algorithm.

  This behaviour defines the interface that all quality function modules
  must implement. Quality functions are responsible for calculating the
  best community move for a given node.
  """

  @doc """
  Find the best community move for a single node.

  Calculates the quality delta for all possible community moves for the
  given node and returns the move with the highest delta.

  ## Parameters

    - `adjacency_matrix` - The adjacency matrix of the graph (n x n tensor)
    - `current_node` - Index of the node to find best move for
    - `community_matrix` - Current community assignment matrix (n x c binary matrix)
    - `total_edges` - Total edge weight in the graph (scalar)
    - `opts` - Options including quality function specific parameters

  ## Returns

    A tuple containing:
    - `best_community` - Community index with highest delta
    - `best_delta` - Quality delta value for the best move

  ## Examples

      iex> {best_community, delta} = QualityModule.best_move(adjacency, 0, community_matrix, 2.0, [resolution: 1.0])
      iex> best_community
      1
      iex> delta
      0.125

  """
  @callback best_move(
              adjacency_matrix :: Nx.Tensor.t(),
              current_node :: non_neg_integer(),
              community_matrix :: Nx.Tensor.t(),
              total_edges :: number(),
              opts :: keyword()
            ) :: {best_community :: non_neg_integer(), best_delta :: float()}
end
