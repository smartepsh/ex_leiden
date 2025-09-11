defmodule ExLeidenTest do
  use ExUnit.Case, async: true
  import Hammox
  alias ExLeiden.Utils

  setup :verify_on_exit!

  describe "ExLeiden.call/2" do
    test "validates function call flow with mocks" do
      input = [{:a, :b}, {:b, :c}]
      opts = [quality_function: :modularity, resolution: 1.5]

      validated_opts = [
        quality_function: :modularity,
        resolution: 1.5,
        max_level: 5,
        theta: 0.01
      ]

      source = %ExLeiden.Source{
        adjacency_matrix: nil,
        degree_sequence: [],
        orphan_communities: []
      }

      leiden_result = %{
        1 => %{communities: [%{id: 0, children: [0, 1]}, %{id: 1, children: [2]}], bridges: []}
      }

      # Set up expectations for the mock calls
      expect(Utils.module(:option), :validate_opts, fn received_opts ->
        assert received_opts == opts
        {:ok, validated_opts}
      end)

      expect(Utils.module(:source), :build!, fn received_input ->
        assert received_input == input
        source
      end)

      expect(Utils.module(:leiden), :call, fn received_source, received_opts ->
        assert received_source == source
        assert received_opts == validated_opts
        leiden_result
      end)

      # Call the function
      result = ExLeiden.call(input, opts)

      # Assert the result
      assert result == {:ok, leiden_result}
    end

    test "handles option validation errors" do
      input = [{:a, :b}]
      opts = [resolution: -1]

      validation_error = {:error, %{resolution: "must be a positive number"}}

      expect(Utils.module(:option), :validate_opts, fn received_opts ->
        assert received_opts == opts
        validation_error
      end)

      # Should not call build! or leiden when validation fails
      # No expectations set for SourceMock or LeidenMock

      result = ExLeiden.call(input, opts)
      assert result == validation_error
    end
  end
end
