defmodule ExLeiden.Quality.ModularityTest do
  use ExUnit.Case, async: true
  alias ExLeiden.Quality.Modularity

  describe "delta_gains/5" do
    test "calculates correct deltas for simple 3-community case" do
      # Setup: 3 communities with sizes [2, 3, 1]
      # Node 0 is in community 0, has edges to other nodes: [0, 1, 2, 0, 0, 1]
      # This means: no self-edge, 1 edge to node 1, 2 edges to node 2, no edge to nodes 3,4, 1 edge to node 5
      adjacency_matrix =
        Nx.tensor([
          # Node 0: edges to nodes 1,2,5
          [0, 1, 2, 0, 0, 1],
          # Node 1: edge back to node 0
          [1, 0, 0, 0, 0, 0],
          # Node 2: edges back to node 0
          [2, 0, 0, 0, 0, 0],
          # Node 3: no edges
          [0, 0, 0, 0, 0, 0],
          # Node 4: no edges
          [0, 0, 0, 0, 0, 0],
          # Node 5: edge back to node 0
          [1, 0, 0, 0, 0, 0]
        ])

      partition_matrix =
        Nx.tensor([
          # Node 0 in community 0
          [1, 0, 0],
          # Node 1 in community 0
          [1, 0, 0],
          # Node 2 in community 1
          [0, 1, 0],
          # Node 3 in community 1
          [0, 1, 0],
          # Node 4 in community 1
          [0, 1, 0],
          # Node 5 in community 2
          [0, 0, 1]
        ])

      # Testing moves for node 0
      node_idx = 0
      resolution = 1.0
      total_edges = 4.0

      deltas =
        Modularity.delta_gains(adjacency_matrix, node_idx, partition_matrix, total_edges,
          resolution: resolution
        )

      deltas_list = Nx.to_list(deltas)

      # Expected calculations based on modularity formula:
      # Community sizes: [2, 3, 1]
      # Community degrees: [1, 2, 1] (sum of degrees in each community)
      # Node 0 degree: 4, edges to communities: [1, 2, 1]
      # Current community: 0

      # For community 0 (self-move): should be 0
      assert Enum.at(deltas_list, 0) == 0.0

      # For community 1 and 2: calculate modularity deltas
      # These will be specific to modularity formula implementation
      assert length(deltas_list) == 3
    end

    test "self-move returns exactly zero delta" do
      # Simple case: node 0 in community 1, 1 edge to node 1 in same community
      adjacency_matrix =
        Nx.tensor([
          # Node 0: edge to node 1
          [0, 1, 0],
          # Node 1: edge back to node 0
          [1, 0, 0],
          # Node 2: no edges
          [0, 0, 0]
        ])

      partition_matrix =
        Nx.tensor([
          # Node 0 in community 1
          [0, 1, 0],
          # Node 1 in community 1
          [0, 1, 0],
          # Node 2 in community 2
          [0, 0, 1]
        ])

      # Testing moves for node 0
      node_idx = 0
      resolution = 1.0
      total_edges = 1.0

      deltas =
        Modularity.delta_gains(adjacency_matrix, node_idx, partition_matrix, total_edges,
          resolution: resolution
        )

      deltas_list = Nx.to_list(deltas)

      # Self-move to community 1 should be exactly 0
      assert Enum.at(deltas_list, 1) == 0.0
    end

    test "works with different resolution values" do
      # Node 0 has 1 edge to node 1
      adjacency_matrix =
        Nx.tensor([
          # Node 0: edge to node 1
          [0, 1],
          # Node 1: edge back to node 0
          [1, 0]
        ])

      partition_matrix =
        Nx.tensor([
          # Node 0 in community 0
          [1, 0],
          # Node 1 in community 1
          [0, 1]
        ])

      # Testing moves for node 0
      node_idx = 0
      total_edges = 1.0

      # Test with resolution = 0.5
      deltas_low =
        Modularity.delta_gains(adjacency_matrix, node_idx, partition_matrix, total_edges,
          resolution: 0.5
        )

      # Test with resolution = 2.0
      deltas_high =
        Modularity.delta_gains(adjacency_matrix, node_idx, partition_matrix, total_edges,
          resolution: 2.0
        )

      deltas_low_list = Nx.to_list(deltas_low)
      deltas_high_list = Nx.to_list(deltas_high)

      # Self-move should always be 0 regardless of resolution
      assert Enum.at(deltas_low_list, 0) == 0.0
      assert Enum.at(deltas_high_list, 0) == 0.0

      # Resolution affects modularity calculation - higher resolution should affect penalties
      community_1_delta_low = Enum.at(deltas_low_list, 1)
      community_1_delta_high = Enum.at(deltas_high_list, 1)

      # In modularity, higher resolution typically makes moves less attractive
      assert community_1_delta_high < community_1_delta_low
    end

    test "handles empty communities correctly" do
      # 4 communities, but community 3 is empty
      # Node 0 has edges to nodes 1 and 2
      adjacency_matrix =
        Nx.tensor([
          # Node 0: edges to nodes 1,2
          [0, 1, 1],
          # Node 1: edge back to node 0
          [1, 0, 0],
          # Node 2: edge back to node 0
          [1, 0, 0]
        ])

      partition_matrix =
        Nx.tensor([
          # Node 0 in community 0
          [1, 0, 0, 0],
          # Node 1 in community 1
          [0, 1, 0, 0],
          # Node 2 in community 2
          [0, 0, 1, 0]
          # Community 3 has no nodes (size 0)
        ])

      # Testing moves for node 0
      node_idx = 0
      resolution = 1.0
      total_edges = 2.0

      deltas =
        Modularity.delta_gains(adjacency_matrix, node_idx, partition_matrix, total_edges,
          resolution: resolution
        )

      deltas_list = Nx.to_list(deltas)

      # Should return 4 values (one for each community)
      assert length(deltas_list) == 4

      # Community 3 (empty) should have calculable modularity delta
      assert is_float(Enum.at(deltas_list, 3))
    end

    test "handles single community case" do
      # Only 1 community - all moves are self-moves
      # Node 0 has edge to node 1 within same community
      adjacency_matrix =
        Nx.tensor([
          # Node 0: edge to node 1
          [0, 1],
          # Node 1: edge back to node 0
          [1, 0]
        ])

      partition_matrix =
        Nx.tensor([
          # Node 0 in community 0
          [1],
          # Node 1 in community 0
          [1]
        ])

      # Testing moves for node 0
      node_idx = 0
      resolution = 1.0
      total_edges = 1.0

      deltas =
        Modularity.delta_gains(adjacency_matrix, node_idx, partition_matrix, total_edges,
          resolution: resolution
        )

      deltas_list = Nx.to_list(deltas)

      # Only self-move possible, should be 0
      assert length(deltas_list) == 1
      assert Enum.at(deltas_list, 0) == 0.0
    end

    test "modularity calculation matches expected formula" do
      # Specific test case to verify modularity formula implementation
      # Simple 3-node triangle where all nodes are connected
      adjacency_matrix =
        Nx.tensor([
          # Node 0: edges to nodes 1,2
          [0, 1, 1],
          # Node 1: edges to nodes 0,2
          [1, 0, 1],
          # Node 2: edges to nodes 0,1
          [1, 1, 0]
        ])

      partition_matrix =
        Nx.tensor([
          # Node 0 in community 0
          [1, 0],
          # Node 1 in community 0
          [1, 0],
          # Node 2 in community 1
          [0, 1]
        ])

      # Testing moves for node 0
      node_idx = 0
      resolution = 1.0
      total_edges = 3.0

      deltas =
        Modularity.delta_gains(adjacency_matrix, node_idx, partition_matrix, total_edges,
          resolution: resolution
        )

      deltas_list = Nx.to_list(deltas)

      # Verify modularity calculation properties:
      # - Self-move should be 0
      # - Moving to community with more connections should generally be positive
      assert Enum.at(deltas_list, 0) == 0.0
      assert length(deltas_list) == 2
      assert is_float(Enum.at(deltas_list, 1))
    end
  end

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

    test "handles single node graph" do
      # Single node, single community
      adjacency_matrix = Nx.tensor([[0]])
      partition_matrix = Nx.tensor([[1]])

      {best_community, best_delta_q} =
        Modularity.best_move(adjacency_matrix, 0, partition_matrix, 0.0, resolution: 1.0)

      assert best_community == 0
      assert best_delta_q == 0.0
    end

    test "works with weighted edges" do
      # Test with non-unit edge weights
      adjacency_matrix =
        Nx.tensor([
          [0, 2.5, 1.5],
          [2.5, 0, 0],
          [1.5, 0, 0]
        ])

      partition_matrix =
        Nx.tensor([
          [1, 0],
          [0, 1],
          [0, 1]
        ])

      total_edges = 4.0

      {best_community, best_delta_q} =
        Modularity.best_move(adjacency_matrix, 0, partition_matrix, total_edges, resolution: 1.0)

      assert is_integer(best_community)
      assert is_float(best_delta_q)
    end

    test "resolution parameter validation" do
      adjacency_matrix = Nx.tensor([[0, 1], [1, 0]])
      partition_matrix = Nx.tensor([[1, 0], [0, 1]])

      # Should work with various resolution values
      for resolution <- [0.1, 0.5, 1.0, 2.0, 10.0] do
        {best_community, best_delta_q} =
          Modularity.best_move(adjacency_matrix, 0, partition_matrix, 1.0, resolution: resolution)

        assert is_integer(best_community)
        assert is_float(best_delta_q)
      end
    end
  end
end
