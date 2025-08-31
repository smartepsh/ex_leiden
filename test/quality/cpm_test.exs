defmodule ExLeiden.Quality.CPMTest do
  use ExUnit.Case, async: true

  alias ExLeiden.Quality.CPM

  describe "best_move/5" do
    test "returns current community with 0 delta for empty graph" do
      adjacency_matrix = Nx.tensor([[0, 0], [0, 0]])
      community_matrix = Nx.eye(2)
      total_edges = 0
      opts = [resolution: 1.0]

      {best_community, delta} =
        CPM.best_move(adjacency_matrix, 0, community_matrix, total_edges, opts)

      # Node 0 stays in community 0
      assert best_community == 0
      assert delta == 0.0
    end

    test "validates return type is tuple with integer and float" do
      adjacency_matrix = Nx.tensor([[0, 1], [1, 0]])
      community_matrix = Nx.eye(2)
      total_edges = 1.0
      opts = [resolution: 1.0]

      assert {0, 0.0} =
               CPM.best_move(adjacency_matrix, 0, community_matrix, total_edges, opts)
    end

    test "handles different resolution parameters" do
      adjacency_matrix = Nx.tensor([[0, 1, 1], [1, 0, 0], [1, 0, 0]])
      community_matrix = Nx.eye(3)
      total_edges = 2.0

      # Test with different resolution values
      assert {1, 0.5} =
               CPM.best_move(adjacency_matrix, 0, community_matrix, total_edges, resolution: 0.5)

      assert {0, 0.0} =
               CPM.best_move(adjacency_matrix, 0, community_matrix, total_edges, resolution: 2.0)
    end
  end
end
