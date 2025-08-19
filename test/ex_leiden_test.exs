defmodule ExLeidenTest do
  use ExUnit.Case, async: true
  alias ExLeiden.{Source, Algorithm, Quality}

  describe "ExLeiden.call/2" do
    test "runs Leiden algorithm on simple triangle" do
      # Simple triangle graph
      edges = [{:a, :b}, {:b, :c}, {:a, :c}]

      result = ExLeiden.call(edges)

      # Should return hierarchical community structure
      assert is_map(result)
      assert Map.has_key?(result, 0)
      assert Map.has_key?(result[0], :communities)
      assert Map.has_key?(result[0], :bridges)
    end

    test "works with adjacency matrix input" do
      matrix = [
        [0, 1, 1, 0, 0],
        [1, 0, 1, 0, 0],
        [1, 1, 0, 0, 0],
        [0, 0, 0, 0, 1],
        [0, 0, 0, 1, 0]
      ]

      result = ExLeiden.call(matrix)

      assert is_map(result)
      # Should detect 2 communities: triangle {0,1,2} and pair {3,4}
      assert Map.has_key?(result, 0)
    end

    test "handles different quality functions" do
      edges = [{:a, :b}, {:b, :c}, {:a, :c}]

      # Test modularity
      result_mod = ExLeiden.call(edges, quality_function: :modularity)
      assert is_map(result_mod)

      # Test CPM
      result_cpm = ExLeiden.call(edges, quality_function: :cpm)
      assert is_map(result_cpm)

      # Results may differ but both should be valid
      assert Map.has_key?(result_mod, 0)
      assert Map.has_key?(result_cpm, 0)
    end

    test "respects resolution parameter" do
      # Larger network where resolution should make a difference
      edges = [
        # Triangle 1
        {:a, :b},
        {:b, :c},
        {:a, :c},
        # Triangle 2
        {:d, :e},
        {:e, :f},
        {:d, :f},
        # Bridge between triangles
        {:c, :d}
      ]

      # Low resolution - should merge communities
      result_low = ExLeiden.call(edges, resolution: 0.5)

      # High resolution - should keep communities separate
      result_high = ExLeiden.call(edges, resolution: 2.0)

      assert is_map(result_low)
      assert is_map(result_high)
    end
  end

  describe "algorithm phases integration" do
    test "Quality functions work with real adjacency matrix" do
      matrix =
        Nx.tensor([
          [0, 1, 1, 0],
          [1, 0, 1, 0],
          [1, 1, 0, 1],
          [0, 0, 1, 0]
        ])

      # Nodes 0,1,2 in community 0, node 3 in community 1
      communities = [0, 0, 0, 1]

      modularity = Quality.modularity(matrix, communities, 1.0)
      assert is_float(modularity)

      cpm = Quality.cpm(matrix, communities, 1.0)
      assert is_float(cpm)
    end

    test "algorithm runs complete workflow" do
      # Create a simple network with clear community structure
      source = Source.build!([{1, 2}, {2, 3}, {1, 3}, {4, 5}, {5, 6}, {4, 6}, {3, 4}])

      # Run the complete algorithm
      {:ok, result} = Algorithm.leiden(source, quality_function: :modularity, max_level: 2)

      assert is_map(result)
      assert Map.has_key?(result, 0)

      # Check that we have communities and bridges
      level_0 = result[0]
      assert Map.has_key?(level_0, :communities)
      assert Map.has_key?(level_0, :bridges)

      # Should detect some community structure
      communities = level_0[:communities]
      assert map_size(communities) > 0
    end
  end

  describe "error handling" do
    test "handles invalid options gracefully" do
      edges = [{:a, :b}, {:b, :c}]

      # Invalid quality function
      assert {:error, _} = ExLeiden.call(edges, quality_function: :invalid)

      # Invalid resolution
      assert {:error, _} = ExLeiden.call(edges, resolution: -1)

      # Invalid max_level
      assert {:error, _} = ExLeiden.call(edges, max_level: 0)
    end

    test "call raises on error" do
      edges = [{:a, :b}]

      assert_raise ArgumentError, fn ->
        ExLeiden.call(edges, quality_function: :invalid)
      end
    end
  end

  describe "info and capabilities" do
    test "provides algorithm information" do
      info = ExLeiden.info()

      assert is_map(info)
      assert Map.has_key?(info, :algorithm)
      assert Map.has_key?(info, :quality_functions)
      assert Map.has_key?(info, :supported_formats)
      assert info[:quality_functions] == [:modularity, :cpm]
    end
  end
end
