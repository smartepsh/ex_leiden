defmodule ExLeiden.Leiden.LocalMoveTest do
  use ExUnit.Case, async: true
  # Nx.Tensor can't use Hammox to validate type
  import Mox

  alias ExLeiden.Leiden.LocalMove
  alias ExLeiden.Source

  setup :verify_on_exit!

  describe "call/2" do
    test "processes nodes and makes community moves" do
      adjacency_matrix = Nx.tensor([[0, 1], [1, 0]])
      source = %Source{adjacency_matrix: adjacency_matrix}
      opts = [quality_function: :modularity, resolution: 1.0]

      # Expect two calls - handle nodes in any order due to shuffled queue
      ExLeiden.Quality.ModularityMock
      |> expect(:best_move, 3, fn _, node, _, _, _ ->
        case node do
          # Node 0 moves to community 1
          0 -> {1, 0.1}
          # Node 1 stays, no improvement
          1 -> {1, 0.0}
        end
      end)

      result = LocalMove.call(source, opts)

      # Verify result structure
      assert {2, 2} = Nx.shape(result)

      # Each row should sum to 1 (each node in exactly one community)
      row_sums = Nx.sum(result, axes: [1]) |> Nx.to_flat_list()
      assert row_sums == [1, 1]
    end

    test "converges when no moves are beneficial" do
      adjacency_matrix = Nx.tensor([[0, 1], [1, 0]])
      source = %Source{adjacency_matrix: adjacency_matrix}
      opts = [quality_function: :modularity, resolution: 1.0]

      # Both nodes stay in their current communities - handle any order
      ExLeiden.Quality.ModularityMock
      |> expect(:best_move, fn _, node, _, _, _ ->
        case node do
          # Node 0 stays in community 0
          0 -> {0, 0.0}
          # Node 1 stays in community 1
          1 -> {1, 0.0}
        end
      end)
      |> expect(:best_move, fn _, node, _, _, _ ->
        case node do
          # Node 0 stays in community 0
          0 -> {0, 0.0}
          # Node 1 stays in community 1
          1 -> {1, 0.0}
        end
      end)

      result = LocalMove.call(source, opts)

      # Should be identity matrix (no moves)
      expected = Nx.eye(2)
      assert Nx.equal(result, expected) |> Nx.all() |> Nx.to_number() == 1
    end
  end
end
