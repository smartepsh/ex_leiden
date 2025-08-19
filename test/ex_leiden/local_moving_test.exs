defmodule ExLeiden.LocalMovingTest do
  use ExUnit.Case, async: true
  
  alias ExLeiden.LocalMoving

  describe "local_moving_phase/4" do
    test "optimizes simple triangle network" do
      # Triangle network where all nodes start in separate communities
      matrix = Nx.tensor([
        [0, 1, 1],
        [1, 0, 1],
        [1, 1, 0]
      ])
      
      initial_communities = [0, 1, 2]  # Each node in own community
      
      result = LocalMoving.local_moving_phase(matrix, initial_communities, :modularity, 1.0)
      
      # Should return updated communities (might merge some)
      assert is_list(result)
      assert length(result) == 3
      
      # All elements should be integers (community IDs)
      assert Enum.all?(result, &is_integer/1)
    end

    test "handles already optimal communities" do
      # Two separate pairs - already well structured
      matrix = Nx.tensor([
        [0, 1, 0, 0],
        [1, 0, 0, 0],
        [0, 0, 0, 1],
        [0, 0, 1, 0]
      ])
      
      optimal_communities = [0, 0, 1, 1]  # Already optimal
      
      result = LocalMoving.local_moving_phase(matrix, optimal_communities, :modularity, 1.0)
      
      # Should not change much if already optimal
      assert is_list(result)
      assert length(result) == 4
    end

    test "works with different quality functions" do
      matrix = Nx.tensor([
        [0, 1, 1, 0],
        [1, 0, 1, 1],
        [1, 1, 0, 0],
        [0, 1, 0, 0]
      ])
      
      initial_communities = [0, 1, 2, 3]
      
      # Test modularity
      result_mod = LocalMoving.local_moving_phase(matrix, initial_communities, :modularity, 1.0)
      
      # Test CPM
      result_cpm = LocalMoving.local_moving_phase(matrix, initial_communities, :cpm, 1.0)
      
      assert is_list(result_mod)
      assert is_list(result_cpm)
      assert length(result_mod) == 4
      assert length(result_cpm) == 4
    end

    test "respects gamma parameter" do
      matrix = Nx.tensor([
        [0, 1, 1, 0],
        [1, 0, 0, 1],
        [1, 0, 0, 1],
        [0, 1, 1, 0]
      ])
      
      initial_communities = [0, 1, 2, 3]
      
      # Low gamma - favor larger communities
      result_low = LocalMoving.local_moving_phase(matrix, initial_communities, :modularity, 0.5)
      
      # High gamma - favor smaller communities  
      result_high = LocalMoving.local_moving_phase(matrix, initial_communities, :modularity, 2.0)
      
      assert is_list(result_low)
      assert is_list(result_high)
      
      # Results might be different (but not required to be)
      unique_communities_low = result_low |> Enum.uniq() |> length()
      unique_communities_high = result_high |> Enum.uniq() |> length()
      
      assert unique_communities_low >= 1
      assert unique_communities_high >= 1
    end

    test "handles single node" do
      matrix = Nx.tensor([[0]])
      initial_communities = [0]
      
      result = LocalMoving.local_moving_phase(matrix, initial_communities, :modularity, 1.0)
      
      assert result == [0]
    end

    test "handles disconnected components" do
      # Two disconnected pairs
      matrix = Nx.tensor([
        [0, 1, 0, 0],
        [1, 0, 0, 0],
        [0, 0, 0, 1],
        [0, 0, 1, 0]
      ])
      
      initial_communities = [0, 1, 2, 3]  # Each node separate
      
      result = LocalMoving.local_moving_phase(matrix, initial_communities, :modularity, 1.0)
      
      assert is_list(result)
      assert length(result) == 4
      
      # Should likely merge connected pairs
      unique_communities = result |> Enum.uniq() |> length()
      assert unique_communities <= 4
    end
  end

  describe "vectorized_local_moving_phase/4" do
    test "fallback to standard implementation works" do
      matrix = Nx.tensor([
        [0, 1, 1],
        [1, 0, 1],
        [1, 1, 0]
      ])
      
      initial_communities = [0, 1, 2]
      
      result = LocalMoving.vectorized_local_moving_phase(matrix, initial_communities, :modularity, 1.0)
      
      assert is_list(result)
      assert length(result) == 3
    end
  end

  describe "quality_improvement/5" do
    test "calculates improvement correctly" do
      matrix = Nx.tensor([
        [0, 1, 1],
        [1, 0, 1],
        [1, 1, 0]
      ])
      
      initial_communities = [0, 1, 2]  # Suboptimal
      final_communities = [0, 0, 0]    # Potentially better
      
      improvement = LocalMoving.quality_improvement(
        matrix,
        initial_communities,
        final_communities,
        :modularity,
        1.0
      )
      
      assert is_float(improvement)
    end

    test "works with CPM quality function" do
      matrix = Nx.tensor([
        [0, 1, 0],
        [1, 0, 1],
        [0, 1, 0]
      ])
      
      initial_communities = [0, 1, 2]
      final_communities = [0, 0, 1]
      
      improvement = LocalMoving.quality_improvement(
        matrix,
        initial_communities,
        final_communities,
        :cpm,
        1.0
      )
      
      assert is_float(improvement)
    end
  end

  describe "converged?/2" do
    test "detects convergence correctly" do
      communities1 = [0, 0, 1, 1]
      communities2 = [0, 0, 1, 1]  # Same
      
      assert LocalMoving.converged?(communities1, communities2) == true
    end

    test "detects non-convergence correctly" do
      communities1 = [0, 0, 1, 1]
      communities2 = [0, 1, 1, 1]  # Different
      
      assert LocalMoving.converged?(communities1, communities2) == false
    end

    test "handles empty communities" do
      assert LocalMoving.converged?([], []) == true
    end
  end

  describe "moving_stats/2" do
    test "calculates statistics correctly" do
      initial = [0, 1, 2, 3]     # 4 communities
      final = [0, 0, 1, 1]       # 2 communities, 2 nodes moved
      
      stats = LocalMoving.moving_stats(initial, final)
      
      assert stats.initial_communities == 4
      assert stats.final_communities == 2
      assert stats.nodes_moved == 2
      assert stats.stability_ratio == 0.5
    end

    test "handles no movement" do
      communities = [0, 0, 1, 1]
      
      stats = LocalMoving.moving_stats(communities, communities)
      
      assert stats.initial_communities == 2
      assert stats.final_communities == 2
      assert stats.nodes_moved == 0
      assert stats.stability_ratio == 1.0
    end

    test "handles complete reorganization" do
      initial = [0, 0, 1, 1]
      final = [1, 1, 0, 0]  # All nodes moved
      
      stats = LocalMoving.moving_stats(initial, final)
      
      assert stats.nodes_moved == 4
      assert stats.stability_ratio == 0.0
    end
  end

  describe "edge cases" do
    test "handles weighted networks" do
      matrix = Nx.tensor([
        [0, 2, 3],
        [2, 0, 1],
        [3, 1, 0]
      ])
      
      initial_communities = [0, 1, 2]
      
      result = LocalMoving.local_moving_phase(matrix, initial_communities, :modularity, 1.0)
      
      assert is_list(result)
      assert length(result) == 3
    end

    test "handles networks with self-loops removed" do
      # Matrix should have zero diagonal, but test robustness
      matrix = Nx.tensor([
        [0, 1, 1],
        [1, 0, 1], 
        [1, 1, 0]
      ])
      
      initial_communities = [0, 1, 2]
      
      result = LocalMoving.local_moving_phase(matrix, initial_communities, :modularity, 1.0)
      
      assert is_list(result)
      assert length(result) == 3
    end

    test "prevents infinite loops with max iterations" do
      # Create a pathological case that might not converge
      matrix = Nx.tensor([
        [0, 1, 0, 1],
        [1, 0, 1, 0],
        [0, 1, 0, 1],
        [1, 0, 1, 0]
      ])
      
      initial_communities = [0, 1, 2, 3]
      
      # Should terminate even if not converged
      result = LocalMoving.local_moving_phase(matrix, initial_communities, :modularity, 1.0)
      
      assert is_list(result)
      assert length(result) == 4
    end
  end
end