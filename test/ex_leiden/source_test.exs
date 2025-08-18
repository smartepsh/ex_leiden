defmodule ExLeiden.SourceTest do
  use ExUnit.Case, async: true

  alias ExLeiden.Source

  describe "build!/1 with adjacency matrix" do
    test "with a valid adjacency matrix" do
      # Define a valid adjacency matrix
      matrix =
        Nx.tensor([
          [0, 1, 0],
          [1, 0, 1],
          [0, 1, 0]
        ])

      # Call the function
      result = Source.build!(matrix)

      # Define the expected result
      expected_result = %Source{
        adjacency_matrix: matrix,
        orphan_communities: [],
        degree_sequence: [0, 1, 2]
      }

      # Assert that the result matches the expected result
      assert result == expected_result
    end

    test "with an adjacency matrix containing orphans" do
      # Define an adjacency matrix with orphan nodes
      matrix =
        Nx.tensor([
          [0, 0, 0],
          [0, 0, 1],
          [0, 1, 0]
        ])

      # Call the function
      result = Source.build!(matrix)

      # Define the expected result
      expected_result = %Source{
        adjacency_matrix:
          Nx.tensor([
            [0, 1],
            [1, 0]
          ]),
        orphan_communities: [0],
        degree_sequence: [1, 2]
      }

      # Assert that the result matches the expected result
      assert result == expected_result
    end

    test "with a non-square matrix" do
      # Define a non-square matrix
      matrix =
        Nx.tensor([
          [0, 1],
          [1, 0],
          [0, 1]
        ])

      # Assert that the function raises an error
      assert_raise ArgumentError, "It's not a valid adjacency matrix", fn ->
        Source.build!(matrix)
      end

      # Define a non-square matrix
      matrix =
        Nx.tensor([
          [[0], [1]],
          [[0], [1]]
        ])

      # Assert that the function raises an error
      assert_raise ArgumentError, "It's not a valid adjacency matrix", fn ->
        Source.build!(matrix)
      end
    end

    test "with a matrix having non-zero diagonal" do
      # Define a matrix with a non-zero diagonal
      matrix =
        Nx.tensor([
          [1, 1, 0],
          [1, 0, 1],
          [0, 1, 0]
        ])

      # Assert that the function raises an error
      assert_raise ArgumentError, "It's not a valid adjacency matrix", fn ->
        Source.build!(matrix)
      end
    end

    test "with a matrix containing negative numbers" do
      # Define a matrix with negative numbers
      matrix =
        Nx.tensor([
          [0, -1, 0],
          [-1, 0, 1],
          [0, 1, 0]
        ])

      # Assert that the function raises an error
      assert_raise ArgumentError, "It's not a valid adjacency matrix", fn ->
        Source.build!(matrix)
      end
    end

    test "with a matrix containing infinity or NaN" do
      # Define a matrix with infinity
      matrix_with_inf =
        Nx.tensor([
          [0, :infinity, 0],
          [:infinity, 0, 1],
          [0, 1, 0]
        ])

      # Assert that the function raises an error
      assert_raise ArgumentError, "It's not a valid adjacency matrix", fn ->
        Source.build!(matrix_with_inf)
      end

      # Define a matrix with NaN
      matrix_with_nan =
        Nx.tensor([
          [0, :nan, 0],
          [:nan, 0, 1],
          [0, 1, 0]
        ])

      # Assert that the function raises an error
      assert_raise ArgumentError, "It's not a valid adjacency matrix", fn ->
        Source.build!(matrix_with_nan)
      end
    end

    test "with a non-symmetric matrix" do
      # Define a non-symmetric matrix
      matrix =
        Nx.tensor([
          [0, 1, 0],
          [0, 0, 1],
          [0, 1, 0]
        ])

      # Assert that the function raises an error
      assert_raise ArgumentError, "It's not a valid adjacency matrix", fn ->
        Source.build!(matrix)
      end
    end
  end

  describe "build!/1 with edge list" do
    test "with simple unweighted edge list" do
      edges = [{:a, :b}, {:b, :c}, {:a, :c}]

      # For fully connected triangle, matrix is same regardless of vertex ordering
      expected_matrix =
        Nx.tensor([
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ])

      assert %Source{
               adjacency_matrix: ^expected_matrix,
               orphan_communities: [],
               degree_sequence: [:a, :b, :c]
             } = Source.build!(edges)
    end

    test "with weighted edge list" do
      edges = [{:a, :b, 2}, {:b, :c, 3}, {:a, :c, 1}]

      # Vertex order: [:a, :b, :c] (alphabetically sorted)
      # Edges: {:a,:b,2} -> [0,1], {:b,:c,3} -> [1,2], {:a,:c,1} -> [0,2]
      expected_matrix =
        Nx.tensor([
          # :a connects to :b(2) and :c(1)
          [0, 2, 1],
          # :b connects to :a(2) and :c(3)
          [2, 0, 3],
          # :c connects to :a(1) and :b(3)
          [1, 3, 0]
        ])

      assert %Source{
               adjacency_matrix: ^expected_matrix,
               orphan_communities: [],
               degree_sequence: [:a, :b, :c]
             } = Source.build!(edges)
    end

    test "with mixed weighted and unweighted edges" do
      # Mix of 2-tuples and 3-tuples
      edges = [{:a, :b}, {:b, :c, 5}, {:a, :c, 2}]

      # Vertex order: [:a, :b, :c] (alphabetically sorted)
      # Edges: {:a,:b} -> [0,1] weight 1, {:b,:c,5} -> [1,2], {:a,:c,2} -> [0,2]
      expected_matrix =
        Nx.tensor([
          # :a connects to :b(1) and :c(2)
          [0, 1, 2],
          # :b connects to :a(1) and :c(5)
          [1, 0, 5],
          # :c connects to :a(2) and :b(5)
          [2, 5, 0]
        ])

      assert %Source{
               adjacency_matrix: ^expected_matrix,
               orphan_communities: [],
               degree_sequence: [:a, :b, :c]
             } = Source.build!(edges)
    end

    test "with duplicate edges" do
      # Same edge specified multiple times should be additive
      edges = [{:a, :b}, {:a, :b}, {:b, :c, 3}]

      # Vertex order: [:a, :b, :c] (alphabetically sorted)
      # Edges: {:a,:b} twice -> [0,1] weight 1+1=2, {:b,:c,3} -> [1,2]
      expected_matrix =
        Nx.tensor([
          # :a connects to :b(2) - duplicate 1+1
          [0, 2, 0],
          # :b connects to :a(2) and :c(3)
          [2, 0, 3],
          # :c connects to :b(3)
          [0, 3, 0]
        ])

      assert %Source{
               adjacency_matrix: ^expected_matrix,
               orphan_communities: [],
               degree_sequence: [:a, :b, :c]
             } = Source.build!(edges)
    end

    test "with invalid edge format - non-tuple elements" do
      # Edge list contains non-tuple elements
      edges = [{:a, :b}, :invalid_edge, {:b, :c}]

      assert_raise FunctionClauseError, fn ->
        Source.build!(edges)
      end
    end

    test "with invalid edge format - tuple with non-number weight" do
      # Edge list contains 3-tuple with non-numeric weight
      edges = [{:a, :b}, {:b, :c, "invalid_weight"}]

      assert_raise FunctionClauseError, fn ->
        Source.build!(edges)
      end
    end
  end

  describe "build!/1 with 2D array weights" do
    test "with valid symmetric 2D array" do
      # Valid adjacency matrix as 2D array
      matrix = [
        [0, 1, 1],
        [1, 0, 1],
        [1, 1, 0]
      ]

      expected_matrix =
        Nx.tensor([
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ])

      assert %Source{
               adjacency_matrix: ^expected_matrix,
               orphan_communities: [],
               degree_sequence: [0, 1, 2]
             } = Source.build!(matrix)
    end

    test "with weighted 2D array" do
      # Weighted adjacency matrix as 2D array
      matrix = [
        [0, 2, 3],
        [2, 0, 1],
        [3, 1, 0]
      ]

      expected_matrix =
        Nx.tensor([
          [0, 2, 3],
          [2, 0, 1],
          [3, 1, 0]
        ])

      assert %Source{
               adjacency_matrix: ^expected_matrix,
               orphan_communities: [],
               degree_sequence: [0, 1, 2]
             } = Source.build!(matrix)
    end

    test "with 2D array containing orphan nodes" do
      # Matrix with orphan node (index 0 has no connections)
      matrix = [
        [0, 0, 0],
        [0, 0, 1],
        [0, 1, 0]
      ]

      # After removing orphan, only indices 1,2 remain
      expected_matrix =
        Nx.tensor([
          [0, 1],
          [1, 0]
        ])

      assert %Source{
               adjacency_matrix: ^expected_matrix,
               orphan_communities: [0],
               degree_sequence: [1, 2]
             } = Source.build!(matrix)
    end

    test "with invalid 2D array - non-number weights" do
      # Matrix with non-numeric weights should fail when creating tensor
      matrix = [
        [0, "invalid", 0],
        ["invalid", 0, 1],
        [0, 1, 0]
      ]

      assert_raise ArgumentError, fn ->
        Source.build!(matrix)
      end
    end

    test "with invalid 2D array" do
      # Matrix with NaN weights should fail validation
      matrix = [
        [0, 0, 0],
        [0, 0, 1],
        [0, 1]
      ]

      assert_raise ArgumentError,
                   "cannot build tensor because lists have different shapes, got {3} at position 0 and {2} at position 3",
                   fn ->
                     Source.build!(matrix)
                   end
    end
  end
end
