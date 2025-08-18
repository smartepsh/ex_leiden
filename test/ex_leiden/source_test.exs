defmodule ExLeiden.SourceTest do
  use ExUnit.Case, async: true

  alias ExLeiden.Source

  describe "build!/1" do
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
end
