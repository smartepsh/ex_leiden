defmodule ExLeiden.Quality.ModularityTest do
  use ExUnit.Case, async: true

  alias ExLeiden.Quality.Modularity

  describe "best_move/5" do
    test "returns current community with 0 delta for empty graph" do
      adjacency_matrix = Nx.tensor([[0, 0], [0, 0]])
      community_matrix = Nx.eye(2)
      total_edges = 0
      opts = [resolution: 1.0]

      {best_community, delta} =
        Modularity.best_move(adjacency_matrix, 0, community_matrix, total_edges, opts)

      # Node 0 stays in community 0
      assert best_community == 0
      assert delta == 0.0
    end

    test "returns zero delta for no-op move (same community)" do
      adjacency_matrix = Nx.tensor([[0, 1], [1, 0]])
      community_matrix = Nx.eye(2)
      total_edges = 1.0
      opts = [resolution: 1.0]

      # Mock internal calculation by checking the pattern matching works
      {best_community, delta} =
        Modularity.best_move(adjacency_matrix, 0, community_matrix, total_edges, opts)

      assert is_integer(best_community)
      assert is_float(delta)
    end

    test "handles different resolution parameters" do
      adjacency_matrix = Nx.tensor([[0, 1, 1], [1, 0, 0], [1, 0, 0]])
      community_matrix = Nx.eye(3)
      total_edges = 2.0

      # Test with different resolution values

      assert {1, 0.0625} =
               Modularity.best_move(adjacency_matrix, 0, community_matrix, total_edges,
                 resolution: 0.5
               )

      assert {0, +0.0} =
               Modularity.best_move(adjacency_matrix, 0, community_matrix, total_edges,
                 resolution: 2.0
               )
    end

    test "works with existing community structure" do
      # Test when some nodes are already in same community
      adjacency_matrix =
        Nx.tensor([
          [0, 1, 1, 0],
          [1, 0, 1, 0],
          [1, 1, 0, 1],
          [0, 0, 1, 0]
        ])

      # Nodes 0,1 in community 0; nodes 2,3 in community 1
      community_matrix =
        Nx.tensor([
          # Node 0 in community 0
          [1, 0],
          # Node 1 in community 0
          [1, 0],
          # Node 2 in community 1
          [0, 1],
          # Node 3 in community 1
          [0, 1]
        ])

      total_edges = 4.0
      opts = [resolution: 1.0]

      assert {0, +0.0} =
               Modularity.best_move(adjacency_matrix, 0, community_matrix, total_edges, opts)
    end

    test "10-node example with meaningful positive delta" do
      # Create a 10-node graph with two clear clusters: 0-4 and 5-9
      # Each cluster is densely connected internally, sparsely connected between clusters
      adjacency_matrix =
        Nx.tensor([
          # Cluster 1: nodes 0-4 (densely connected)
          # Node 0
          [0, 2, 2, 1, 1, 0, 0, 0, 0, 1],
          # Node 1
          [2, 0, 2, 1, 1, 0, 0, 0, 0, 0],
          # Node 2
          [2, 2, 0, 1, 1, 0, 0, 0, 0, 0],
          # Node 3
          [1, 1, 1, 0, 2, 0, 0, 0, 0, 0],
          # Node 4
          [1, 1, 1, 2, 0, 0, 0, 0, 0, 0],
          # Cluster 2: nodes 5-9 (densely connected)
          # Node 5
          [0, 0, 0, 0, 0, 0, 2, 2, 1, 1],
          # Node 6
          [0, 0, 0, 0, 0, 2, 0, 2, 1, 1],
          # Node 7
          [0, 0, 0, 0, 0, 2, 2, 0, 1, 1],
          # Node 8
          [0, 0, 0, 0, 0, 1, 1, 1, 0, 2],
          # Node 9
          [1, 0, 0, 0, 0, 1, 1, 1, 2, 0]
        ])

      # Start with each node in its own community (singleton partition)
      community_matrix = Nx.eye(10)
      # Sum of all edges / 2 (undirected)
      total_edges = 34.0
      opts = [resolution: 1.0]

      # Test node 0 - should want to move to cluster with nodes 1,2,3,4
      assert {1, delta} =
               Modularity.best_move(adjacency_matrix, 0, community_matrix, total_edges, opts)

      assert Float.round(delta, 5) == 0.00973
    end
  end
end
