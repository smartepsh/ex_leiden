defmodule ExLeiden.RefinementTest do
  use ExUnit.Case, async: true
  
  alias ExLeiden.Refinement

  describe "refine_communities/2" do
    test "leaves connected communities unchanged" do
      # Triangle - fully connected community
      matrix = Nx.tensor([
        [0, 1, 1],
        [1, 0, 1],
        [1, 1, 0]
      ])
      
      communities = [0, 0, 0]  # All in same community
      
      result = Refinement.refine_communities(matrix, communities)
      
      # Should remain unchanged since triangle is connected
      assert result == communities
    end

    test "splits disconnected communities" do
      # Two disconnected pairs in same community
      matrix = Nx.tensor([
        [0, 1, 0, 0],
        [1, 0, 0, 0],
        [0, 0, 0, 1],
        [0, 0, 1, 0]
      ])
      
      communities = [0, 0, 0, 0]  # All in same community (incorrect)
      
      result = Refinement.refine_communities(matrix, communities)
      
      # Should split into 2 communities since there are 2 disconnected components
      unique_communities = result |> Enum.uniq() |> length()
      assert unique_communities == 2
      
      # Nodes 0,1 should be in one community, nodes 2,3 in another
      assert result |> Enum.at(0) == result |> Enum.at(1)
      assert result |> Enum.at(2) == result |> Enum.at(3)
      assert result |> Enum.at(0) != result |> Enum.at(2)
    end

    test "handles multiple communities with mixed connectivity" do
      # Complex network: connected triangle + disconnected pair in same community
      matrix = Nx.tensor([
        [0, 1, 1, 0, 0],
        [1, 0, 1, 0, 0],
        [1, 1, 0, 0, 0],
        [0, 0, 0, 0, 1],
        [0, 0, 0, 1, 0]
      ])
      
      # Triangle (0,1,2) and pair (3,4) incorrectly in same community
      # Plus another properly connected community (none here)
      communities = [0, 0, 0, 0, 0]
      
      result = Refinement.refine_communities(matrix, communities)
      
      # Should split the disconnected parts
      unique_communities = result |> Enum.uniq() |> length()
      assert unique_communities >= 2
      
      # Triangle should stay together
      triangle_community = result |> Enum.at(0)
      assert result |> Enum.at(1) == triangle_community
      assert result |> Enum.at(2) == triangle_community
      
      # Pair should be together but separate from triangle
      pair_community = result |> Enum.at(3)
      assert result |> Enum.at(4) == pair_community
      assert pair_community != triangle_community
    end

    test "handles single node communities" do
      matrix = Nx.tensor([
        [0, 1, 0],
        [1, 0, 0],
        [0, 0, 0]
      ])
      
      communities = [0, 0, 1]  # Node 2 is isolated
      
      result = Refinement.refine_communities(matrix, communities)
      
      # Single nodes are trivially connected
      assert is_list(result)
      assert length(result) == 3
    end

    test "preserves community IDs when possible" do
      matrix = Nx.tensor([
        [0, 1, 0, 0],
        [1, 0, 0, 0],
        [0, 0, 0, 1],
        [0, 0, 1, 0]
      ])
      
      communities = [5, 5, 5, 5]  # Using non-standard community ID
      
      result = Refinement.refine_communities(matrix, communities)
      
      # First component should keep original ID
      assert 5 in result
      
      # Should have 2 communities total
      unique_communities = result |> Enum.uniq() |> length()
      assert unique_communities == 2
    end
  end

  describe "community_connected?/3" do
    test "correctly identifies connected communities" do
      # Triangle
      matrix = Nx.tensor([
        [0, 1, 1],
        [1, 0, 1],
        [1, 1, 0]
      ])
      
      communities = [0, 0, 0]
      
      result = Refinement.community_connected?(matrix, communities, 0)
      assert result == true
    end

    test "correctly identifies disconnected communities" do
      # Two separate pairs
      matrix = Nx.tensor([
        [0, 1, 0, 0],
        [1, 0, 0, 0],
        [0, 0, 0, 1],
        [0, 0, 1, 0]
      ])
      
      communities = [0, 0, 0, 0]  # All in same community (disconnected)
      
      result = Refinement.community_connected?(matrix, communities, 0)
      assert result == false
    end

    test "handles single node communities" do
      matrix = Nx.tensor([[0]])
      communities = [0]
      
      result = Refinement.community_connected?(matrix, communities, 0)
      assert result == true  # Single node is trivially connected
    end

    test "handles empty communities" do
      matrix = Nx.tensor([[0, 1], [1, 0]])
      communities = [0, 1]
      
      result = Refinement.community_connected?(matrix, communities, 2)  # Non-existent community
      assert result == true  # Empty community is trivially connected
    end

    test "handles path graphs" do
      # Linear path: 0-1-2
      matrix = Nx.tensor([
        [0, 1, 0],
        [1, 0, 1],
        [0, 1, 0]
      ])
      
      communities = [0, 0, 0]
      
      result = Refinement.community_connected?(matrix, communities, 0)
      assert result == true  # Path is connected
    end
  end

  describe "split_disconnected_community/3" do
    test "splits disconnected community correctly" do
      # Two separate pairs
      matrix = Nx.tensor([
        [0, 1, 0, 0],
        [1, 0, 0, 0],
        [0, 0, 0, 1],
        [0, 0, 1, 0]
      ])
      
      communities = [0, 0, 0, 0]
      
      components = Refinement.split_disconnected_community(matrix, communities, 0)
      
      assert length(components) == 2
      
      # Each component should have 2 nodes
      assert Enum.all?(components, &(length(&1) == 2))
      
      # All original nodes should be accounted for
      all_nodes = components |> List.flatten() |> Enum.sort()
      assert all_nodes == [0, 1, 2, 3]
    end

    test "returns single component for connected community" do
      # Triangle
      matrix = Nx.tensor([
        [0, 1, 1],
        [1, 0, 1],
        [1, 1, 0]
      ])
      
      communities = [0, 0, 0]
      
      components = Refinement.split_disconnected_community(matrix, communities, 0)
      
      assert length(components) == 1
      assert hd(components) |> Enum.sort() == [0, 1, 2]
    end

    test "handles single node communities" do
      matrix = Nx.tensor([[0, 1], [1, 0]])
      communities = [0, 1]
      
      components = Refinement.split_disconnected_community(matrix, communities, 0)
      
      assert components == [[0]]
    end

    test "handles complex disconnected structures" do
      # Star + isolated pair: 0-1-2, 3-4
      matrix = Nx.tensor([
        [0, 1, 0, 0, 0],
        [1, 0, 1, 0, 0],
        [0, 1, 0, 0, 0],
        [0, 0, 0, 0, 1],
        [0, 0, 0, 1, 0]
      ])
      
      communities = [0, 0, 0, 0, 0]
      
      components = Refinement.split_disconnected_community(matrix, communities, 0)
      
      assert length(components) == 2
      
      # One component with 3 nodes, one with 2
      component_sizes = components |> Enum.map(&length/1) |> Enum.sort()
      assert component_sizes == [2, 3]
    end
  end

  describe "refinement_stats/2" do
    test "calculates statistics correctly when splitting occurs" do
      initial = [0, 0, 0, 0]     # 1 community
      refined = [0, 0, 1, 1]     # 2 communities (1 split)
      
      stats = Refinement.refinement_stats(initial, refined)
      
      assert stats.initial_communities == 1
      assert stats.refined_communities == 2
      assert stats.communities_split == 1
      assert stats.split_ratio == 1.0
    end

    test "calculates statistics when no splitting occurs" do
      communities = [0, 0, 1, 1]
      
      stats = Refinement.refinement_stats(communities, communities)
      
      assert stats.initial_communities == 2
      assert stats.refined_communities == 2
      assert stats.communities_split == 0
      assert stats.split_ratio == 0.0
    end

    test "handles multiple splits" do
      initial = [0, 0, 0, 0, 0, 0]    # 1 community
      refined = [0, 0, 1, 1, 2, 2]    # 3 communities (2 splits)
      
      stats = Refinement.refinement_stats(initial, refined)
      
      assert stats.initial_communities == 1
      assert stats.refined_communities == 3
      assert stats.communities_split == 2
      assert stats.split_ratio == 2.0
    end
  end

  describe "edge cases" do
    test "handles empty input gracefully" do
      matrix = Nx.tensor([], type: :f32) |> Nx.reshape({0, 0})
      communities = []
      
      result = Refinement.refine_communities(matrix, communities)
      assert result == []
    end

    test "handles networks with self-loops (should be removed)" do
      # Matrix with diagonal entries (invalid but test robustness)
      matrix = Nx.tensor([
        [1, 1, 0],  # Self-loop on node 0
        [1, 0, 1],
        [0, 1, 0]
      ])
      
      communities = [0, 0, 0]
      
      # Should still work (self-loops should be ignored in connectivity)
      result = Refinement.refine_communities(matrix, communities)
      assert is_list(result)
      assert length(result) == 3
    end

    test "handles weighted networks" do
      matrix = Nx.tensor([
        [0, 2, 0, 0],
        [2, 0, 0, 0],
        [0, 0, 0, 3],
        [0, 0, 3, 0]
      ])
      
      communities = [0, 0, 0, 0]
      
      result = Refinement.refine_communities(matrix, communities)
      
      # Should split into 2 communities based on connectivity
      unique_communities = result |> Enum.uniq() |> length()
      assert unique_communities == 2
    end

    test "handles large community IDs and non-integer IDs" do
      matrix = Nx.tensor([
        [0, 1, 0, 0],
        [1, 0, 0, 0],
        [0, 0, 0, 1],
        [0, 0, 1, 0]
      ])
      
      # Using atom community IDs
      communities = [:big_community, :big_community, :big_community, :big_community]
      
      result = Refinement.refine_communities(matrix, communities)
      
      # Should handle non-integer IDs gracefully
      assert is_list(result)
      assert length(result) == 4
      
      # Should have 2 unique communities
      unique_communities = result |> Enum.uniq() |> length()
      assert unique_communities == 2
    end
  end
end