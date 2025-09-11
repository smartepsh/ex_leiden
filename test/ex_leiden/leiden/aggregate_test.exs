defmodule ExLeiden.Leiden.AggregateTest do
  use ExUnit.Case, async: true
  import Mox
  alias ExLeiden.Leiden.Aggregate
  alias ExLeiden.Source

  setup :verify_on_exit!

  # Helper function to create expected Source struct
  defp build_expected_source(adjacency_matrix) do
    degree_sequence =
      adjacency_matrix
      |> Nx.sum(axes: [1])
      |> Nx.to_list()

    %Source{
      adjacency_matrix: adjacency_matrix,
      degree_sequence: degree_sequence,
      orphan_communities: []
    }
  end

  describe "call/2 - aggregation functionality" do
    test "aggregates simple path graph with two communities" do
      # Path graph: 0---1---2---3
      # Communities: {0,1} and {2,3}
      adjacency_matrix =
        Nx.tensor([
          [0, 1, 0, 0],
          [1, 0, 1, 0],
          [0, 1, 0, 1],
          [0, 0, 1, 0]
        ])

      partition_matrix =
        Nx.tensor([
          [1, 0],
          [1, 0],
          [0, 1],
          [0, 1]
        ])

      # Expected aggregate matrix after C^T * A * C with diagonal zeroing
      expected_aggregate =
        Nx.tensor([
          # Inter-community connection
          [0, 1],
          # Symmetric
          [1, 0]
        ])

      expected_source = build_expected_source(expected_aggregate)

      expect(ExLeiden.SourceMock, :build!, fn ^expected_aggregate ->
        expected_source
      end)

      %Source{adjacency_matrix: result_adj, degree_sequence: result_degrees} =
        Aggregate.call(adjacency_matrix, partition_matrix)

      # Verify the aggregated matrix structure
      assert Nx.shape(result_adj) == {2, 2}
      assert length(result_degrees) == 2

      # Check that the matrix has the connection between communities
      total_edges = Nx.sum(result_adj) |> Nx.to_number()
      # Symmetric edge between two communities
      assert total_edges == 2

      # Check symmetry is preserved
      assert Nx.equal(result_adj, Nx.transpose(result_adj)) |> Nx.all() |> Nx.to_number() == 1

      # Check diagonal is zero (no self-loops)
      diagonal = Nx.take_diagonal(result_adj) |> Nx.to_list()
      assert diagonal == [0, 0]
    end

    test "aggregates triangle graph into single community" do
      # Triangle graph: all nodes connected to each other
      adjacency_matrix =
        Nx.tensor([
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ])

      # All nodes in one community
      partition_matrix =
        Nx.tensor([
          [1],
          [1],
          [1]
        ])

      # Expected: single node with zero connections (diagonal zeroed)
      expected_aggregate = Nx.tensor([[0]])
      expected_source = build_expected_source(expected_aggregate)

      expect(ExLeiden.SourceMock, :build!, fn ^expected_aggregate ->
        expected_source
      end)

      %Source{adjacency_matrix: result_adj, degree_sequence: result_degrees} =
        Aggregate.call(adjacency_matrix, partition_matrix)

      # Single community results in 1x1 matrix
      assert Nx.shape(result_adj) == {1, 1}
      assert length(result_degrees) == 1
      # Diagonal is zero
      assert Nx.to_number(result_adj[0][0]) == 0
    end

    test "aggregates disconnected components" do
      # Two disconnected triangles
      adjacency_matrix =
        Nx.tensor([
          # Component 1: nodes 0,1
          [0, 1, 0, 0],
          [1, 0, 0, 0],
          # Component 2: nodes 2,3
          [0, 0, 0, 1],
          [0, 0, 1, 0]
        ])

      # Each component forms its own community
      partition_matrix =
        Nx.tensor([
          [1, 0],
          [1, 0],
          [0, 1],
          [0, 1]
        ])

      # Expected: no connections between communities
      expected_aggregate =
        Nx.tensor([
          # No inter-community edges
          [0, 0],
          [0, 0]
        ])

      expected_source = build_expected_source(expected_aggregate)

      expect(ExLeiden.SourceMock, :build!, fn ^expected_aggregate ->
        expected_source
      end)

      %Source{adjacency_matrix: result_adj} =
        Aggregate.call(adjacency_matrix, partition_matrix)

      # Check that no edges exist between disconnected components
      total_edges = Nx.sum(result_adj) |> Nx.to_number()
      assert total_edges == 0

      # Check all entries are zero
      assert Nx.equal(result_adj, Nx.broadcast(0, {2, 2})) |> Nx.all() |> Nx.to_number() == 1
    end

    test "aggregates weighted edges correctly" do
      # Weighted path: 0--5--1--2--2
      adjacency_matrix =
        Nx.tensor([
          [0, 5, 0, 0],
          [5, 0, 2, 0],
          [0, 2, 0, 2],
          [0, 0, 2, 0]
        ])

      partition_matrix =
        Nx.tensor([
          [1, 0],
          [1, 0],
          [0, 1],
          [0, 1]
        ])

      # Expected: weight 2 connection between communities (from edge 1→2)
      expected_aggregate =
        Nx.tensor([
          # Inter-community weight
          [0, 2],
          # Symmetric
          [2, 0]
        ])

      expected_source = build_expected_source(expected_aggregate)

      expect(ExLeiden.SourceMock, :build!, fn ^expected_aggregate ->
        expected_source
      end)

      %Source{adjacency_matrix: result_adj} =
        Aggregate.call(adjacency_matrix, partition_matrix)

      # Check that weights are properly aggregated
      assert Nx.shape(result_adj) == {2, 2}

      # Check that the inter-community edge has weight 2 (from edge 1→2)
      total_weight = Nx.sum(result_adj) |> Nx.to_number()
      # Two entries of weight 2 (symmetric)
      assert total_weight == 4

      # Check symmetry is preserved
      assert Nx.equal(result_adj, Nx.transpose(result_adj)) |> Nx.all() |> Nx.to_number() == 1

      # Check diagonal is zero
      diagonal = Nx.take_diagonal(result_adj) |> Nx.to_list()
      assert diagonal == [0, 0]
    end

    test "preserves symmetry for undirected graphs with multiple connections" do
      # Test with multiple connections between communities
      adjacency_matrix =
        Nx.tensor([
          [0, 1, 2, 0],
          [1, 0, 1, 0],
          [2, 1, 0, 3],
          [0, 0, 3, 0]
        ])

      partition_matrix =
        Nx.tensor([
          [1, 0],
          [1, 0],
          [0, 1],
          [0, 1]
        ])

      # Expected: aggregated weights between communities
      # Community 0: nodes 0,1; Community 1: nodes 2,3
      # Inter-community edges: 0→2 (weight 2), 1→2 (weight 1) = total 3
      expected_aggregate =
        Nx.tensor([
          # Aggregated inter-community weight
          [0, 3],
          # Symmetric
          [3, 0]
        ])

      expected_source = build_expected_source(expected_aggregate)

      expect(ExLeiden.SourceMock, :build!, fn ^expected_aggregate ->
        expected_source
      end)

      %Source{adjacency_matrix: result_adj} = Aggregate.call(adjacency_matrix, partition_matrix)

      # Check symmetry: result_adj[i][j] should equal result_adj[j][i]
      assert Nx.equal(result_adj, Nx.transpose(result_adj))
             |> Nx.all()
             |> Nx.to_number() == 1

      # Verify the aggregated weight
      total_weight = Nx.sum(result_adj) |> Nx.to_number()
      # 3 + 3 (symmetric)
      assert total_weight == 6
    end
  end

  describe "matrix operations" do
    test "diagonal is always zero for identity partition" do
      # Each node in its own community - should result in zero matrix
      adjacency_matrix =
        Nx.tensor([
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ])

      # Each node in separate community
      partition_matrix = Nx.eye(3)

      # Expected: original adjacency matrix with diagonal zeroed
      # For identity partition, C^T * A * C = A, then diagonal is zeroed
      expected_aggregate =
        Nx.tensor([
          # Original adjacency with diagonal zeroed
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ])

      expected_source = build_expected_source(expected_aggregate)

      expect(ExLeiden.SourceMock, :build!, fn ^expected_aggregate ->
        expected_source
      end)

      %Source{adjacency_matrix: result_adj} = Aggregate.call(adjacency_matrix, partition_matrix)

      # Extract diagonal and verify it's zero
      diagonal = Nx.take_diagonal(result_adj)
      zero_diagonal = Nx.broadcast(0, Nx.shape(diagonal))

      assert Nx.equal(diagonal, zero_diagonal) |> Nx.all() |> Nx.to_number() == 1

      # Result should equal original adjacency matrix with diagonal zeroed
      expected_final = Nx.tensor([[0, 1, 1], [1, 0, 1], [1, 1, 0]])
      assert Nx.equal(result_adj, expected_final) |> Nx.all() |> Nx.to_number() == 1
    end

    test "handles complex community structures" do
      # 4-node graph with mixed community assignment
      adjacency_matrix =
        Nx.tensor([
          [0, 2, 1, 0],
          [2, 0, 0, 1],
          [1, 0, 0, 3],
          [0, 1, 3, 0]
        ])

      # Communities: {0,2} and {1,3}
      partition_matrix =
        Nx.tensor([
          [1, 0],
          [0, 1],
          [1, 0],
          [0, 1]
        ])

      # Calculate expected aggregation manually:
      # C^T * A * C where C is partition matrix, A is adjacency matrix
      # Inter-community edges: 0→1 (weight 2), 0→3 (weight 0), 2→1 (weight 0), 2→3 (weight 3) = total 5
      expected_aggregate =
        Nx.tensor([
          [0, 5],
          [5, 0]
        ])

      expected_source = build_expected_source(expected_aggregate)

      expect(ExLeiden.SourceMock, :build!, fn ^expected_aggregate ->
        expected_source
      end)

      %Source{adjacency_matrix: result_adj} = Aggregate.call(adjacency_matrix, partition_matrix)

      # Verify structure
      assert Nx.shape(result_adj) == {2, 2}

      # Check diagonal is zero
      diagonal = Nx.take_diagonal(result_adj) |> Nx.to_list()
      assert diagonal == [0, 0]

      # Check symmetry
      assert Nx.equal(result_adj, Nx.transpose(result_adj)) |> Nx.all() |> Nx.to_number() == 1

      # Verify the aggregated weight
      total_weight = Nx.sum(result_adj) |> Nx.to_number()
      # 5 + 5 (symmetric)
      assert total_weight == 10
    end
  end
end
