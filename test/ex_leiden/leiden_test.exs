defmodule ExLeiden.LeidenTest do
  use ExUnit.Case, async: true

  import Mox

  alias ExLeiden.{Leiden, Source}

  setup :verify_on_exit!

  describe "call/2" do
    test "calls local move and stops when all communities are singletons" do
      matrix = [[0, 1], [1, 0]]
      source = Source.build!(matrix)
      opts = [max_level: 1, resolution: 1.0, community_size_threshold: nil]

      # Mock local move returning singleton communities
      singleton_matrix = Nx.tensor([[1, 0], [0, 1]])

      expect(ExLeiden.Leiden.LocalMoveMock, :call, fn _source, _opts ->
        singleton_matrix
      end)

      result = Leiden.call(source, opts)

      # When all communities are singletons, algorithm stops early
      assert result == %{}
    end

    test "calls all phases when communities are not singletons" do
      matrix = [[0, 1, 1], [1, 0, 1], [1, 1, 0]]
      source = Source.build!(matrix)
      opts = [max_level: 1, resolution: 1.0, community_size_threshold: nil]

      # Mock non-singleton communities to trigger full pipeline
      # 2 communities: nodes {0,1} in community 0, node {2} in community 1
      community_matrix = Nx.tensor([[1, 0], [1, 0], [0, 1]])
      refined_matrix = Nx.tensor([[1, 0], [1, 0], [0, 1]])

      expect(ExLeiden.Leiden.LocalMoveMock, :call, fn _source, _opts ->
        community_matrix
      end)

      expect(ExLeiden.Leiden.RefinePartitionMock, :call, fn _adj_matrix, _comm_matrix, _opts ->
        refined_matrix
      end)

      expect(ExLeiden.Leiden.AggregateMock, :call, fn _adj_matrix, _comm_matrix ->
        # Create single-node source that represents complete aggregation
        single_node_matrix = Nx.tensor([[0.0]])

        %Source{
          adjacency_matrix: single_node_matrix,
          orphan_communities: [],
          degree_sequence: [0]
        }
      end)

      result = Leiden.call(source, opts)

      assert %{1 => {communities, bridges}} = result
      # Community 0 has nodes [0, 1], Community 1 has node [2]
      assert [%{id: 0, children: [0, 1]}, %{id: 1, children: [2]}] =
               Enum.sort_by(communities, & &1.id)

      assert [] = bridges
    end

    test "respects max_level limit" do
      matrix = [[0, 1], [1, 0]]
      source = Source.build!(matrix)
      opts = [max_level: 0, resolution: 1.0, community_size_threshold: nil]

      # Should stop immediately without calling any modules
      result = Leiden.call(source, opts)

      assert result == %{}
    end

    test "continues to next level when max_level allows" do
      matrix = [[0, 1], [1, 0]]
      source = Source.build!(matrix)
      opts = [max_level: 2, resolution: 1.0, community_size_threshold: nil]

      # First level - non-singletons
      # Both nodes in same community
      community_matrix = Nx.tensor([[1, 0], [1, 0]])
      refined_matrix = Nx.tensor([[1, 0], [1, 0]])
      # Create single-node source for level 2
      single_node_matrix = Nx.tensor([[0.0]])

      aggregated_source = %Source{
        adjacency_matrix: single_node_matrix,
        orphan_communities: [],
        degree_sequence: [0]
      }

      # Level 1 calls
      expect(ExLeiden.Leiden.LocalMoveMock, :call, 2, fn source_arg, _opts ->
        if Nx.shape(source_arg.adjacency_matrix) == {2, 2} do
          # Original graph
          community_matrix
        else
          # Aggregated graph - singleton to stop
          Nx.tensor([[1]])
        end
      end)

      expect(ExLeiden.Leiden.RefinePartitionMock, :call, fn _adj_matrix, _comm_matrix, _opts ->
        refined_matrix
      end)

      expect(ExLeiden.Leiden.AggregateMock, :call, fn _adj_matrix, _comm_matrix ->
        aggregated_source
      end)

      result = Leiden.call(source, opts)

      assert %{1 => {communities, bridges}} = result
      # Community 0 has both nodes, Community 1 is empty (from the matrix [[1,0],[1,0]])
      assert [%{id: 0, children: [0, 1]}, %{id: 1, children: []}] =
               Enum.sort_by(communities, & &1.id)

      assert [] = bridges
    end
  end

  describe "algorithm flow logic" do
    test "verifies correct parameter passing between phases" do
      matrix = [[0, 1, 0], [1, 0, 1], [0, 1, 0]]
      source = Source.build!(matrix)

      opts = [
        max_level: 1,
        resolution: 1.0,
        quality_function: :modularity,
        community_size_threshold: nil
      ]

      community_matrix = Nx.tensor([[1, 0], [0, 1], [0, 1]])

      # Verify that options are passed correctly
      expect(ExLeiden.Leiden.LocalMoveMock, :call, fn _source, received_opts ->
        assert Keyword.get(received_opts, :resolution) == 1.0
        assert Keyword.get(received_opts, :quality_function) == :modularity
        community_matrix
      end)

      expect(ExLeiden.Leiden.RefinePartitionMock, :call, fn adj_matrix,
                                                            comm_matrix,
                                                            received_opts ->
        # Verify adjacency matrix is passed from source
        assert Nx.shape(adj_matrix) == {3, 3}
        # Verify community matrix comes from local move
        assert Nx.shape(comm_matrix) == {3, 2}
        # Verify options are passed through
        assert Keyword.get(received_opts, :resolution) == 1.0
        community_matrix
      end)

      expect(ExLeiden.Leiden.AggregateMock, :call, fn adj_matrix, comm_matrix ->
        # Verify both matrices are passed correctly
        assert Nx.shape(adj_matrix) == {3, 3}
        assert Nx.shape(comm_matrix) == {3, 2}
        # Create single-node source that represents complete aggregation
        single_node_matrix = Nx.tensor([[0.0]])

        %Source{
          adjacency_matrix: single_node_matrix,
          orphan_communities: [],
          degree_sequence: [0]
        }
      end)

      result = Leiden.call(source, opts)

      assert is_map(result)
      # When no phases run due to parameter passing test, result should be empty
      # or have proper structure if mocks trigger algorithm flow
    end

    test "creates communities from refinement matrix correctly" do
      matrix = [[0, 1], [1, 0]]
      source = Source.build!(matrix)
      opts = [max_level: 1, resolution: 1.0, community_size_threshold: nil]

      # Mock refinement that puts both nodes in same community
      community_matrix = Nx.tensor([[1, 0], [1, 0]])
      # Single community with both nodes
      refined_matrix = Nx.tensor([[1], [1]])

      expect(ExLeiden.Leiden.LocalMoveMock, :call, fn _source, _opts ->
        community_matrix
      end)

      expect(ExLeiden.Leiden.RefinePartitionMock, :call, fn _adj_matrix, _comm_matrix, _opts ->
        refined_matrix
      end)

      expect(ExLeiden.Leiden.AggregateMock, :call, fn _adj_matrix, _comm_matrix ->
        # Create single-node source that represents complete aggregation
        single_node_matrix = Nx.tensor([[0.0]])

        %Source{
          adjacency_matrix: single_node_matrix,
          orphan_communities: [],
          degree_sequence: [0]
        }
      end)

      result = Leiden.call(source, opts)

      assert %{1 => {[%{id: 0, children: [0, 1]}], []}} = result
    end
  end

  describe "community size threshold termination" do
    test "terminates when community size threshold is reached" do
      matrix = [[0, 1, 0], [1, 0, 1], [0, 1, 0]]
      source = Source.build!(matrix)

      # Set threshold to 3 - should terminate immediately since we have 3 communities
      opts = [max_level: 5, community_size_threshold: 3]

      result = Leiden.call(source, opts)

      # Should terminate immediately without calling any algorithm phases
      assert result == %{}
    end

    test "continues when community size is above threshold" do
      matrix = [[0, 1, 0, 0], [1, 0, 1, 0], [0, 1, 0, 1], [0, 0, 1, 0]]
      source = Source.build!(matrix)

      # Set threshold to 2 - should continue since we have 4 communities > 2
      opts = [max_level: 1, community_size_threshold: 2]

      # Mock the algorithm phases
      community_matrix = Nx.tensor([[1, 0], [1, 0], [0, 1], [0, 1]])

      expect(ExLeiden.Leiden.LocalMoveMock, :call, fn _source, _opts ->
        community_matrix
      end)

      expect(ExLeiden.Leiden.RefinePartitionMock, :call, fn _adj_matrix, _comm_matrix, _opts ->
        community_matrix
      end)

      expect(ExLeiden.Leiden.AggregateMock, :call, fn _adj_matrix, _comm_matrix ->
        # Return aggregated source with 2 communities (exactly at threshold)
        aggregated_matrix = Nx.tensor([[0.0, 1.0], [1.0, 0.0]])

        %Source{
          adjacency_matrix: aggregated_matrix,
          orphan_communities: [],
          degree_sequence: [1, 1]
        }
      end)

      result = Leiden.call(source, opts)

      # Should run one level and then terminate because aggregated result has 2 communities (= threshold)
      assert %{1 => _} = result
    end

    test "community size threshold takes precedence over max_level" do
      matrix = [[0, 1], [1, 0]]
      source = Source.build!(matrix)

      # Set high max_level but low threshold - threshold should win
      opts = [max_level: 10, community_size_threshold: 2]

      result = Leiden.call(source, opts)

      # Should terminate immediately because we have 2 communities = threshold
      assert result == %{}
    end

    test "ignores threshold when set to nil" do
      matrix = [[0, 1], [1, 0]]
      source = Source.build!(matrix)
      opts = [max_level: 0, community_size_threshold: nil]

      result = Leiden.call(source, opts)

      # Should respect max_level instead of threshold
      assert result == %{}
    end
  end

  describe "bridge extraction" do
    test "extracts bridges from aggregated matrix with multiple communities" do
      matrix = [[0, 1, 0, 0], [1, 0, 1, 0], [0, 1, 0, 1], [0, 0, 1, 0]]
      source = Source.build!(matrix)
      opts = [max_level: 1, resolution: 1.0, community_size_threshold: nil]

      # Mock to create 2 communities: {0,1} and {2,3}
      community_matrix = Nx.tensor([[1, 0], [1, 0], [0, 1], [0, 1]])
      refined_matrix = community_matrix

      # Mock aggregated matrix with inter-community connection
      # Weight 1 between communities
      aggregated_matrix = Nx.tensor([[0.0, 1.0], [1.0, 0.0]])

      aggregated_source = %Source{
        adjacency_matrix: aggregated_matrix,
        orphan_communities: [],
        degree_sequence: [0, 1]
      }

      expect(ExLeiden.Leiden.LocalMoveMock, :call, fn _source, _opts ->
        community_matrix
      end)

      expect(ExLeiden.Leiden.RefinePartitionMock, :call, fn _adj_matrix, _comm_matrix, _opts ->
        refined_matrix
      end)

      expect(ExLeiden.Leiden.AggregateMock, :call, fn _adj_matrix, _comm_matrix ->
        aggregated_source
      end)

      result = Leiden.call(source, opts)

      # Verify bridges were extracted correctly
      assert %{1 => {communities, bridges}} = result
      assert [{0, 1, 1.0}] = bridges

      assert [%{id: 0, children: [0, 1]}, %{id: 1, children: [2, 3]}] =
               Enum.sort_by(communities, & &1.id)
    end

    test "handles sparse matrices with no bridges" do
      matrix = [[0, 1], [1, 0]]
      source = Source.build!(matrix)
      opts = [max_level: 1, resolution: 1.0, community_size_threshold: nil]

      # Mock to create single community (no bridges possible)
      # Both nodes in same community
      community_matrix = Nx.tensor([[1], [1]])
      refined_matrix = community_matrix

      # Mock aggregated matrix with single community (no inter-community connections)
      # Single community, no self-loops
      aggregated_matrix = Nx.tensor([[0.0]])

      aggregated_source = %Source{
        adjacency_matrix: aggregated_matrix,
        orphan_communities: [],
        degree_sequence: [0]
      }

      expect(ExLeiden.Leiden.LocalMoveMock, :call, fn _source, _opts ->
        community_matrix
      end)

      expect(ExLeiden.Leiden.RefinePartitionMock, :call, fn _adj_matrix, _comm_matrix, _opts ->
        refined_matrix
      end)

      expect(ExLeiden.Leiden.AggregateMock, :call, fn _adj_matrix, _comm_matrix ->
        aggregated_source
      end)

      result = Leiden.call(source, opts)

      # Verify no bridges extracted for single community
      assert %{1 => {[%{id: 0, children: [0, 1]}], []}} = result
    end

    test "extracts multiple bridges from dense aggregated matrix" do
      matrix = [[0, 1, 1, 1], [1, 0, 0, 0], [1, 0, 0, 1], [1, 0, 1, 0]]
      source = Source.build!(matrix)
      opts = [max_level: 1, resolution: 1.0, community_size_threshold: nil]

      # Mock to create 3 communities
      community_matrix = Nx.tensor([[1, 0, 0], [0, 1, 0], [0, 0, 1], [0, 0, 1]])
      refined_matrix = community_matrix

      # Mock aggregated matrix with multiple inter-community connections
      aggregated_matrix =
        Nx.tensor([
          # Community 0 connects to 1 (weight 2.0) and 2 (weight 1.5)
          [0.0, 2.0, 1.5],
          # Community 1 connects to 0 (weight 2.0)
          [2.0, 0.0, 0.0],
          # Community 2 connects to 0 (weight 1.5)
          [1.5, 0.0, 0.0]
        ])

      aggregated_source = %Source{
        adjacency_matrix: aggregated_matrix,
        orphan_communities: [],
        degree_sequence: [0, 1, 2]
      }

      expect(ExLeiden.Leiden.LocalMoveMock, :call, fn _source, _opts ->
        community_matrix
      end)

      expect(ExLeiden.Leiden.RefinePartitionMock, :call, fn _adj_matrix, _comm_matrix, _opts ->
        refined_matrix
      end)

      expect(ExLeiden.Leiden.AggregateMock, :call, fn _adj_matrix, _comm_matrix ->
        aggregated_source
      end)

      result = Leiden.call(source, opts)

      # Verify multiple bridges were extracted correctly (only upper triangle)
      expected_bridges = [
        {0, 1, 2.0},
        {0, 2, 1.5}
      ]

      expected_communities = [
        %{id: 0, children: [0]},
        %{id: 1, children: [1]},
        %{id: 2, children: [2, 3]}
      ]

      assert %{1 => {communities, bridges}} = result
      assert ^expected_bridges = Enum.sort_by(bridges, &{elem(&1, 0), elem(&1, 1)})
      assert ^expected_communities = Enum.sort_by(communities, & &1.id)
    end
  end
end
