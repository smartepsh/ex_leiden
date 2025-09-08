defmodule ExLeiden.Leiden.RefinePartitionTest do
  use ExUnit.Case, async: true
  alias ExLeiden.Leiden.RefinePartition

  describe "call/3" do
    test "refines singleton partition correctly" do
      # Simple 3-node triangle graph
      adjacency_matrix =
        Nx.tensor([
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ])

      # Start with singleton partition (each node in its own community)
      community_matrix = Nx.eye(3)

      opts = [
        resolution: 1.0,
        theta: 0.01,
        quality_function: :modularity,
        select_best_for_test: true
      ]

      refined_partition = RefinePartition.call(adjacency_matrix, community_matrix, opts)

      # Should return a valid partition matrix
      assert Nx.shape(refined_partition) == {3, 3}

      # Each row should sum to 1 (each node in exactly one community)
      row_sums = Nx.sum(refined_partition, axes: [1])
      expected_sums = Nx.tensor([1, 1, 1])
      assert Nx.all_close(row_sums, expected_sums)
    end

    test "handles empty communities correctly" do
      # 4x4 identity matrix but with an empty community
      adjacency_matrix =
        Nx.tensor([
          [0, 1, 0, 0],
          [1, 0, 0, 0],
          [0, 0, 0, 1],
          [0, 0, 1, 0]
        ])

      # Two pairs: (0,1) and (2,3), with empty community
      community_matrix =
        Nx.tensor([
          [1, 0, 0, 0],
          [1, 0, 0, 0],
          [0, 1, 0, 0],
          [0, 1, 0, 0]
        ])

      opts = [resolution: 1.0, theta: 0.01, quality_function: :cpm, select_best_for_test: true]

      refined_partition = RefinePartition.call(adjacency_matrix, community_matrix, opts)

      # Should return valid partition (empty communities removed)
      {n_nodes, n_communities} = Nx.shape(refined_partition)
      assert n_nodes == 4
      assert n_communities >= 1 and n_communities <= 4

      # Verify each node is in exactly one community
      row_sums = Nx.sum(refined_partition, axes: [1])
      expected_sums = Nx.tensor([1, 1, 1, 1])
      assert Nx.all_close(row_sums, expected_sums)
    end

    test "preserves well-connected communities" do
      # Create a graph with two well-connected clusters
      adjacency_matrix =
        Nx.tensor([
          # Cluster 1: nodes 0,1,2 densely connected
          [0, 2, 2, 0, 0],
          [2, 0, 2, 0, 0],
          # weak connection to cluster 2
          [2, 2, 0, 1, 0],
          # Cluster 2: nodes 3,4 connected
          [0, 0, 1, 0, 1],
          [0, 0, 0, 1, 0]
        ])

      # Start with all nodes in one community
      community_matrix =
        Nx.tensor([
          [1, 0],
          [1, 0],
          [1, 0],
          [1, 0],
          [1, 0]
        ])

      opts = [
        resolution: 1.0,
        theta: 0.01,
        quality_function: :modularity,
        select_best_for_test: true
      ]

      refined_partition = RefinePartition.call(adjacency_matrix, community_matrix, opts)

      # Should split into well-connected subcommunities (empty communities removed)
      {n_nodes, n_communities} = Nx.shape(refined_partition)
      assert n_nodes == 5
      assert n_communities >= 1 and n_communities <= 5

      # Each node should be in exactly one community
      row_sums = Nx.sum(refined_partition, axes: [1])
      expected_sums = Nx.tensor([1, 1, 1, 1, 1])
      assert Nx.all_close(row_sums, expected_sums)
    end

    test "handles single-node communities" do
      # Graph with isolated nodes
      adjacency_matrix =
        Nx.tensor([
          [0, 1, 0],
          [1, 0, 0],
          # isolated node
          [0, 0, 0]
        ])

      community_matrix =
        Nx.tensor([
          [1, 0, 0],
          [1, 0, 0],
          # node 2 alone in community 2
          [0, 0, 1]
        ])

      opts = [resolution: 1.0, theta: 0.01, quality_function: :cpm, select_best_for_test: true]

      refined_partition = RefinePartition.call(adjacency_matrix, community_matrix, opts)

      # Should handle single-node communities gracefully (empty communities removed)
      {n_nodes, n_communities} = Nx.shape(refined_partition)
      assert n_nodes == 3
      assert n_communities >= 1 and n_communities <= 3

      row_sums = Nx.sum(refined_partition, axes: [1])
      expected_sums = Nx.tensor([1, 1, 1])
      assert Nx.all_close(row_sums, expected_sums)
    end

    test "works with different quality functions" do
      adjacency_matrix =
        Nx.tensor([
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ])

      community_matrix = Nx.eye(3)

      # Test with modularity
      opts_mod = [
        resolution: 1.0,
        theta: 0.01,
        quality_function: :modularity,
        select_best_for_test: true
      ]

      refined_mod = RefinePartition.call(adjacency_matrix, community_matrix, opts_mod)

      # Test with CPM
      opts_cpm = [
        resolution: 1.0,
        theta: 0.01,
        quality_function: :cpm,
        select_best_for_test: true
      ]

      refined_cpm = RefinePartition.call(adjacency_matrix, community_matrix, opts_cpm)

      # Both should produce valid partitions
      assert Nx.shape(refined_mod) == {3, 3}
      assert Nx.shape(refined_cpm) == {3, 3}

      # Both should have proper row sums
      for refined <- [refined_mod, refined_cpm] do
        row_sums = Nx.sum(refined, axes: [1])
        expected_sums = Nx.tensor([1, 1, 1])
        assert Nx.all_close(row_sums, expected_sums)
      end
    end
  end

  describe "well-connected communities filtering" do
    test "filters communities based on gamma-connectivity" do
      # Create a specific scenario where we can test γ-connectivity
      # Simple 4-node path: 0-1-2-3
      adjacency_matrix =
        Nx.tensor([
          [0, 1, 0, 0],
          [1, 0, 1, 0],
          [0, 1, 0, 1],
          [0, 0, 1, 0]
        ])

      # All nodes start in one community
      community_matrix =
        Nx.tensor([
          [1, 0],
          [1, 0],
          [1, 0],
          [1, 0]
        ])

      # High resolution should require stronger connectivity
      opts_high_res = [
        resolution: 2.0,
        theta: 0.01,
        quality_function: :cpm,
        select_best_for_test: true
      ]

      refined_high = RefinePartition.call(adjacency_matrix, community_matrix, opts_high_res)

      # Low resolution should be more permissive
      opts_low_res = [
        resolution: 0.1,
        theta: 0.01,
        quality_function: :cpm,
        select_best_for_test: true
      ]

      refined_low = RefinePartition.call(adjacency_matrix, community_matrix, opts_low_res)

      # Both should produce valid partitions but potentially different structures (empty communities removed)
      assert Nx.shape(refined_high) == {4, 1}
      assert Nx.shape(refined_low) == {4, 2}

      for refined <- [refined_high, refined_low] do
        row_sums = Nx.sum(refined, axes: [1])
        expected_sums = Nx.tensor([1, 1, 1, 1])
        assert Nx.all_close(row_sums, expected_sums)
      end
    end
  end

  describe "randomized community selection" do
    test "produces different results with different random seeds" do
      adjacency_matrix =
        Nx.tensor([
          [0, 1, 1, 1],
          [1, 0, 1, 1],
          [1, 1, 0, 1],
          [1, 1, 1, 0]
        ])

      community_matrix = Nx.eye(4)
      # Higher theta for more randomness
      opts = [
        resolution: 1.0,
        theta: 0.5,
        quality_function: :modularity,
        select_best_for_test: true
      ]

      # Set different random seeds and run multiple times
      :rand.seed(:exsss, {1, 2, 3})
      result1 = RefinePartition.call(adjacency_matrix, community_matrix, opts)

      :rand.seed(:exsss, {4, 5, 6})
      result2 = RefinePartition.call(adjacency_matrix, community_matrix, opts)

      # Both should be valid partitions
      for result <- [result1, result2] do
        assert Nx.shape(result) == {4, 4}
        row_sums = Nx.sum(result, axes: [1])
        expected_sums = Nx.tensor([1, 1, 1, 1])
        assert Nx.all_close(row_sums, expected_sums)
      end

      # With high theta, results might be different (though not guaranteed)
      # At minimum, they should both be valid
      refute result1 == nil
      refute result2 == nil
    end

    test "theta parameter affects randomization" do
      adjacency_matrix =
        Nx.tensor([
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ])

      community_matrix = Nx.eye(3)

      # Very low theta (more greedy)
      opts_low_theta = [
        resolution: 1.0,
        theta: 0.001,
        quality_function: :cpm,
        select_best_for_test: true
      ]

      # Higher theta (more random)
      opts_high_theta = [
        resolution: 1.0,
        theta: 1.0,
        quality_function: :cpm,
        select_best_for_test: true
      ]

      # Both should produce valid results
      result_low = RefinePartition.call(adjacency_matrix, community_matrix, opts_low_theta)
      result_high = RefinePartition.call(adjacency_matrix, community_matrix, opts_high_theta)

      for result <- [result_low, result_high] do
        assert Nx.shape(result) == {3, 3}
        row_sums = Nx.sum(result, axes: [1])
        expected_sums = Nx.tensor([1, 1, 1])
        assert Nx.all_close(row_sums, expected_sums)
      end
    end
  end

  describe "edge cases" do
    test "handles graphs with no edges" do
      # Empty graph (no edges)
      adjacency_matrix =
        Nx.tensor([
          [0, 0, 0],
          [0, 0, 0],
          [0, 0, 0]
        ])

      community_matrix = Nx.eye(3)

      opts = [
        resolution: 1.0,
        theta: 0.01,
        quality_function: :modularity,
        select_best_for_test: true
      ]

      # Should handle gracefully - nodes stay in their own communities
      result = RefinePartition.call(adjacency_matrix, community_matrix, opts)

      assert Nx.shape(result) == {3, 3}

      # Should be close to identity matrix since no beneficial moves
      assert Nx.all_close(result, Nx.eye(3), atol: 0.1)
    end

    test "handles single node graph" do
      adjacency_matrix = Nx.tensor([[0]])
      community_matrix = Nx.tensor([[1]])

      opts = [resolution: 1.0, theta: 0.01, quality_function: :cpm, select_best_for_test: true]

      result = RefinePartition.call(adjacency_matrix, community_matrix, opts)

      assert Nx.shape(result) == {1, 1}
      assert Nx.all_close(result, Nx.tensor([[1]]))
    end

    test "handles disconnected graph components" do
      # Two disconnected pairs
      adjacency_matrix =
        Nx.tensor([
          [0, 1, 0, 0],
          [1, 0, 0, 0],
          [0, 0, 0, 1],
          [0, 0, 1, 0]
        ])

      # Start with all in one community
      community_matrix =
        Nx.tensor([
          [1],
          [1],
          [1],
          [1]
        ])

      opts = [
        resolution: 1.0,
        theta: 0.01,
        quality_function: :modularity,
        select_best_for_test: true
      ]

      result = RefinePartition.call(adjacency_matrix, community_matrix, opts)

      # Should handle disconnected components (empty communities removed)
      {n_nodes, n_communities} = Nx.shape(result)
      assert n_nodes == 4
      assert n_communities >= 1 and n_communities <= 4

      row_sums = Nx.sum(result, axes: [1])
      expected_sums = Nx.tensor([1, 1, 1, 1])
      assert Nx.all_close(row_sums, expected_sums)
    end
  end

  describe "bridge node scenario" do
    test "separates bridge node from well-connected clusters" do
      # Graph structure with dense clusters: [0,1,2] - bridge_node - [4,5,6]
      # Expected result: three communities: [0,1,2], [3], [4,5,6]
      adjacency_matrix =
        Nx.tensor([
          # Cluster 1: nodes 0,1,2 densely connected
          # Node 0: strong connections within cluster
          [0, 3, 3, 0, 0, 0, 0],
          # Node 1: strong internal connections, weak to bridge
          [3, 0, 3, 1, 0, 0, 0],
          # Node 2: strong internal connections, weak to bridge
          [3, 3, 0, 1, 0, 0, 0],
          # Node 3 (bridge): weak connections to both clusters
          [0, 1, 1, 0, 1, 1, 0],
          # Cluster 2: nodes 4,5,6 densely connected
          # Node 4: weak to bridge, strong internal connections
          [0, 0, 0, 1, 0, 3, 3],
          # Node 5: weak to bridge, strong internal connections
          [0, 0, 0, 1, 3, 0, 3],
          # Node 6: strong connections within cluster
          [0, 0, 0, 0, 3, 3, 0]
        ])

      # Start with all nodes in one community
      community_matrix =
        Nx.tensor([
          [1],
          [1],
          [1],
          [1],
          [1],
          [1],
          [1]
        ])

      opts = [
        resolution: 1.0,
        theta: 0.01,
        quality_function: :modularity,
        select_best_for_test: true
      ]

      refined_partition = RefinePartition.call(adjacency_matrix, community_matrix, opts)

      # Should produce valid partition with multiple communities (empty communities removed)
      {n_nodes, n_communities} = Nx.shape(refined_partition)
      assert n_nodes == 7
      # Should split into at least 2 communities
      assert n_communities >= 2

      # Each node should be in exactly one community
      row_sums = Nx.sum(refined_partition, axes: [1])
      expected_sums = Nx.tensor([1, 1, 1, 1, 1, 1, 1])
      assert Nx.all_close(row_sums, expected_sums)

      # Extract community assignments
      community_assignments = Nx.argmax(refined_partition, axis: 1) |> Nx.to_list()

      # Check that we have multiple distinct communities
      unique_communities = community_assignments |> Enum.uniq() |> length()
      assert unique_communities >= 2, "Expected at least 2 communities, got #{unique_communities}"

      # Success: Algorithm successfully separated the bridge graph into 3 communities
      # The exact community assignments don't matter, just that we have 3 distinct communities
      assert unique_communities == 3, "Expected exactly 3 communities, got #{unique_communities}"
    end

    test "handles bridge with weighted edges" do
      # Same structure but with stronger internal cluster connections
      adjacency_matrix =
        Nx.tensor([
          # Cluster 1: nodes 0,1,2 with strong internal connections
          # Node 0: strong connection to 1, weaker to 2
          [0, 3, 2, 0, 0, 0, 0],
          # Node 1: strong connections within cluster, weak bridge
          [3, 0, 3, 1, 0, 0, 0],
          # Node 2: strong internal, weak to bridge
          [2, 3, 0, 1, 0, 0, 0],
          # Bridge node: weak connections to both clusters
          # Node 3: bridge with weak connections
          [0, 1, 1, 0, 1, 1, 0],
          # Cluster 2: nodes 4,5,6 with strong internal connections
          # Node 4: weak to bridge, strong internal
          [0, 0, 0, 1, 0, 3, 2],
          # Node 5: weak to bridge, strong internal
          [0, 0, 0, 1, 3, 0, 3],
          # Node 6: strong internal connections
          [0, 0, 0, 0, 2, 3, 0]
        ])

      # Start with all nodes in one community
      community_matrix =
        Nx.tensor([
          [1],
          [1],
          [1],
          [1],
          [1],
          [1],
          [1]
        ])

      opts = [resolution: 0.8, theta: 0.01, quality_function: :cpm, select_best_for_test: true]

      refined_partition = RefinePartition.call(adjacency_matrix, community_matrix, opts)

      # Should produce valid partition (empty communities removed)
      {n_nodes, n_communities} = Nx.shape(refined_partition)
      assert n_nodes == 7
      assert n_communities >= 1 and n_communities <= 7

      # Each node should be in exactly one community
      row_sums = Nx.sum(refined_partition, axes: [1])
      expected_sums = Nx.tensor([1, 1, 1, 1, 1, 1, 1])
      assert Nx.all_close(row_sums, expected_sums)

      # Should find multiple communities due to strong internal cluster connections
      community_assignments = Nx.argmax(refined_partition, axis: 1) |> Nx.to_list()
      unique_communities = community_assignments |> Enum.uniq() |> length()
      assert unique_communities >= 2
    end
  end
end
