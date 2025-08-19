defmodule ExLeiden.AggregationTest do
  use ExUnit.Case, async: true
  
  alias ExLeiden.Aggregation

  describe "aggregate_network/2" do
    test "creates aggregate network for simple communities" do
      # Two separate pairs
      matrix = Nx.tensor([
        [0, 1, 0, 0],
        [1, 0, 0, 0],
        [0, 0, 0, 1],
        [0, 0, 1, 0]
      ])
      
      communities = [0, 0, 1, 1]  # Two communities
      
      {aggregate_matrix, mapping} = Aggregation.aggregate_network(matrix, communities)
      
      # Should create 2x2 matrix for 2 communities
      assert Nx.shape(aggregate_matrix) == {2, 2}
      
      # Diagonal should be zero (no self-loops)
      diagonal = Nx.take_diagonal(aggregate_matrix) |> Nx.to_list()
      assert Enum.all?(diagonal, &(&1 == 0))
      
      # Should have mapping information
      assert is_map(mapping)
      assert Map.has_key?(mapping, :community_to_index)
      assert Map.has_key?(mapping, :index_to_community)
      assert Map.has_key?(mapping, :original_communities)
    end

    test "handles communities with inter-community edges" do
      # Triangle with bridge
      matrix = Nx.tensor([
        [0, 1, 1, 0],
        [1, 0, 1, 1],  # Bridge from node 1 to node 3
        [1, 1, 0, 0],
        [0, 1, 0, 0]
      ])
      
      communities = [0, 0, 0, 1]  # Triangle + single node
      
      {aggregate_matrix, mapping} = Aggregation.aggregate_network(matrix, communities)
      
      # Should be 2x2 matrix
      assert Nx.shape(aggregate_matrix) == {2, 2}
      
      # Should have non-zero off-diagonal (bridge weight)
      matrix_data = aggregate_matrix |> Nx.to_list()
      assert matrix_data |> List.flatten() |> Enum.any?(&(&1 > 0))
      
      # Mapping should contain original communities
      assert mapping.original_communities == [0, 0, 0, 1]
    end

    test "handles single node communities" do
      matrix = Nx.tensor([
        [0, 1, 0],
        [1, 0, 1],
        [0, 1, 0]
      ])
      
      communities = [0, 1, 2]  # Each node in own community
      
      {aggregate_matrix, mapping} = Aggregation.aggregate_network(matrix, communities)
      
      # Should be 3x3 matrix
      assert Nx.shape(aggregate_matrix) == {3, 3}
      
      # Should preserve edge structure
      assert Nx.shape(aggregate_matrix) == Nx.shape(matrix)
      
      # Community mapping should be 1:1
      assert map_size(mapping.community_to_index) == 3
    end

    test "removes self-loops correctly" do
      # Community with internal edges
      matrix = Nx.tensor([
        [0, 1, 1],
        [1, 0, 1],
        [1, 1, 0]
      ])
      
      communities = [0, 0, 0]  # All in same community
      
      {aggregate_matrix, _mapping} = Aggregation.aggregate_network(matrix, communities)
      
      # Should be 1x1 matrix with zero (self-loop removed)
      assert Nx.shape(aggregate_matrix) == {1, 1}
      assert aggregate_matrix |> Nx.to_number() == 0.0
    end
  end

  describe "initial_aggregate_communities/1" do
    test "creates singleton communities" do
      mapping = %{
        community_to_index: %{0 => 0, 1 => 1, 2 => 2},
        index_to_community: %{0 => 0, 1 => 1, 2 => 2},
        original_communities: [0, 0, 1, 1, 2, 2]
      }
      
      result = Aggregation.initial_aggregate_communities(mapping)
      
      assert result == [0, 1, 2]
    end

    test "handles single community" do
      mapping = %{
        community_to_index: %{0 => 0},
        index_to_community: %{0 => 0},
        original_communities: [0, 0, 0]
      }
      
      result = Aggregation.initial_aggregate_communities(mapping)
      
      assert result == [0]
    end
  end

  describe "map_back_to_original/3" do
    test "maps aggregate communities back to original nodes" do
      aggregate_communities = [0, 1]  # Two aggregate communities
      
      mapping = %{
        community_to_index: %{10 => 0, 20 => 1},
        index_to_community: %{0 => 10, 1 => 20},
        original_communities: [10, 10, 20, 20]
      }
      
      level = 1
      
      result = Aggregation.map_back_to_original(aggregate_communities, mapping, level)
      
      # Should create hierarchical IDs
      assert length(result) == 4
      assert Enum.all?(result, fn {l, _c} -> l == level end)
      
      # Nodes in same original community should get same hierarchical community
      assert Enum.at(result, 0) == Enum.at(result, 1)  # Both were in community 10
      assert Enum.at(result, 2) == Enum.at(result, 3)  # Both were in community 20
    end

    test "handles complex mapping" do
      aggregate_communities = [0, 0, 1]  # Aggregate merging
      
      mapping = %{
        community_to_index: %{:a => 0, :b => 1, :c => 2},
        index_to_community: %{0 => :a, 1 => :b, 2 => :c},
        original_communities: [:a, :a, :b, :c, :c]
      }
      
      level = 2
      
      result = Aggregation.map_back_to_original(aggregate_communities, mapping, level)
      
      assert length(result) == 5
      
      # Check hierarchical community assignments
      expected_results = [{2, 0}, {2, 0}, {2, 0}, {2, 1}, {2, 1}]
      assert result == expected_results
    end
  end

  describe "inter_community_weight/4" do
    test "calculates weight between communities correctly" do
      matrix = Nx.tensor([
        [0, 1, 2, 0],
        [1, 0, 1, 3],
        [2, 1, 0, 0],
        [0, 3, 0, 0]
      ])
      
      communities = [0, 0, 0, 1]
      
      # Weight between community 0 and community 1
      weight = Aggregation.inter_community_weight(matrix, communities, 0, 1)
      
      # Should be sum of edges between communities: 0+3+0 = 3
      assert weight == 3.0
    end

    test "returns zero for same community" do
      matrix = Nx.tensor([
        [0, 1, 1],
        [1, 0, 1],
        [1, 1, 0]
      ])
      
      communities = [0, 0, 0]
      
      weight = Aggregation.inter_community_weight(matrix, communities, 0, 0)
      assert weight == 0.0
    end

    test "returns zero for non-existent communities" do
      matrix = Nx.tensor([
        [0, 1],
        [1, 0]
      ])
      
      communities = [0, 1]
      
      weight = Aggregation.inter_community_weight(matrix, communities, 0, 2)  # Community 2 doesn't exist
      assert weight == 0.0
    end

    test "handles weighted networks" do
      matrix = Nx.tensor([
        [0, 5, 0],
        [5, 0, 3],
        [0, 3, 0]
      ])
      
      communities = [0, 1, 1]
      
      weight = Aggregation.inter_community_weight(matrix, communities, 0, 1)
      
      # Should be 5 (edge from node 0 to node 1)
      assert weight == 5.0
    end
  end

  describe "aggregation_stats/3" do
    test "calculates compression statistics" do
      original_matrix = Nx.tensor([
        [0, 1, 0, 0],
        [1, 0, 0, 0],
        [0, 0, 0, 1],
        [0, 0, 1, 0]
      ])
      
      aggregate_matrix = Nx.tensor([
        [0, 0],
        [0, 0]
      ])
      
      mapping = %{community_to_index: %{}}
      
      stats = Aggregation.aggregation_stats(original_matrix, aggregate_matrix, mapping)
      
      assert stats.original_nodes == 4
      assert stats.aggregate_nodes == 2
      assert stats.compression_ratio == 2.0
      assert stats.original_edges == 2.0  # Two pairs
      assert stats.aggregate_edges == 0.0
    end

    test "handles single node compression" do
      original_matrix = Nx.tensor([
        [0, 1, 1],
        [1, 0, 1],
        [1, 1, 0]
      ])
      
      aggregate_matrix = Nx.tensor([[0]])
      
      mapping = %{community_to_index: %{}}
      
      stats = Aggregation.aggregation_stats(original_matrix, aggregate_matrix, mapping)
      
      assert stats.original_nodes == 3
      assert stats.aggregate_nodes == 1
      assert stats.compression_ratio == 3.0
      assert stats.original_edges == 3.0  # Triangle has 3 edges
    end
  end

  describe "should_continue_aggregation?/3" do
    test "continues when conditions are met" do
      mapping = %{
        community_to_index: %{0 => 0, 1 => 1},
        original_communities: [0, 0, 0, 0, 1, 1, 1, 1]  # Good compression
      }
      
      result = Aggregation.should_continue_aggregation?(mapping, 1, 5)
      assert result == true
    end

    test "stops at max level" do
      mapping = %{
        community_to_index: %{0 => 0, 1 => 1},
        original_communities: [0, 0, 1, 1]
      }
      
      result = Aggregation.should_continue_aggregation?(mapping, 5, 5)
      assert result == false
    end

    test "stops with single community" do
      mapping = %{
        community_to_index: %{0 => 0},
        original_communities: [0, 0, 0, 0]
      }
      
      result = Aggregation.should_continue_aggregation?(mapping, 1, 5)
      assert result == false
    end

    test "stops with poor compression" do
      mapping = %{
        community_to_index: %{0 => 0, 1 => 1, 2 => 2, 3 => 3, 4 => 4},
        original_communities: [0, 1, 2, 3, 4]  # No compression
      }
      
      result = Aggregation.should_continue_aggregation?(mapping, 1, 5)
      assert result == false
    end
  end

  describe "build_hierarchy/2" do
    test "builds basic hierarchy structure" do
      all_communities = [
        [0, 0, 1, 1],      # Level 0
        [0, 1]             # Level 1
      ]
      
      all_mappings = [
        %{community_to_index: %{0 => 0, 1 => 1}},
        %{community_to_index: %{0 => 0}}
      ]
      
      hierarchy = Aggregation.build_hierarchy(all_communities, all_mappings)
      
      assert hierarchy.levels == 2
      assert hierarchy.communities_per_level == [2, 1]
      assert Map.has_key?(hierarchy, :relationships)
      assert Map.has_key?(hierarchy, :level_mappings)
    end

    test "handles single level" do
      all_communities = [[0, 1, 2]]
      all_mappings = [%{community_to_index: %{0 => 0, 1 => 1, 2 => 2}}]
      
      hierarchy = Aggregation.build_hierarchy(all_communities, all_mappings)
      
      assert hierarchy.levels == 1
      assert hierarchy.communities_per_level == [3]
    end
  end

  describe "edge cases" do
    test "handles empty communities list" do
      matrix = Nx.tensor([[0]])
      communities = [0]
      
      {aggregate_matrix, mapping} = Aggregation.aggregate_network(matrix, communities)
      
      assert Nx.shape(aggregate_matrix) == {1, 1}
      assert mapping.original_communities == [0]
    end

    test "handles non-sequential community IDs" do
      matrix = Nx.tensor([
        [0, 1, 0, 0],
        [1, 0, 0, 0],
        [0, 0, 0, 1],
        [0, 0, 1, 0]
      ])
      
      communities = [100, 100, 200, 200]  # Non-sequential IDs
      
      {aggregate_matrix, mapping} = Aggregation.aggregate_network(matrix, communities)
      
      assert Nx.shape(aggregate_matrix) == {2, 2}
      assert Map.has_key?(mapping.community_to_index, 100)
      assert Map.has_key?(mapping.community_to_index, 200)
    end

    test "handles string community IDs" do
      matrix = Nx.tensor([
        [0, 1, 0],
        [1, 0, 1],
        [0, 1, 0]
      ])
      
      communities = ["red", "blue", "blue"]
      
      {aggregate_matrix, mapping} = Aggregation.aggregate_network(matrix, communities)
      
      assert Nx.shape(aggregate_matrix) == {2, 2}
      assert Map.has_key?(mapping.community_to_index, "red")
      assert Map.has_key?(mapping.community_to_index, "blue")
    end

    test "handles very sparse networks" do
      # Mostly disconnected network
      matrix = Nx.tensor([
        [0, 0, 0, 0],
        [0, 0, 1, 0],
        [0, 1, 0, 0],
        [0, 0, 0, 0]
      ])
      
      communities = [0, 1, 1, 2]
      
      {aggregate_matrix, mapping} = Aggregation.aggregate_network(matrix, communities)
      
      assert Nx.shape(aggregate_matrix) == {3, 3}
      
      # Most entries should be zero
      matrix_data = aggregate_matrix |> Nx.to_list() |> List.flatten()
      zero_count = matrix_data |> Enum.count(&(&1 == 0))
      assert zero_count >= 6  # At least diagonal + most off-diagonal entries
    end
  end
end