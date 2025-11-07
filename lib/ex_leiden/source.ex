defmodule ExLeiden.Source do
  import Nx.Defn

  @moduledoc """
  Internal representation of graph data for the Leiden algorithm.

  Converts various input formats into a standardized adjacency matrix representation, using Nx tensors for efficient numerical computation.

  ## Graph Input Processing

  The Source module handles conversion of various graph input formats into a standardized internal representation with adjacency matrices for efficient computation. Key features include:

  - **Format Conversion** - Accepts edge lists, 2D arrays, {vertices, edges} tuples, Nx tensors, and Graph structs
  - **Vertex Ordering** - Maintains deterministic alphabetical ordering for consistent results
  - **Orphan Detection** - Identifies and handles isolated vertices with no connections
  - **Matrix Validation** - Ensures adjacency matrices are square, symmetric, non-negative, and have zero diagonals
  - **Weight Processing** - Supports both weighted and unweighted edges, with automatic symmetrization

  ## Source Struct

  The Source struct contains:

  - `adjacency_matrix` - Nx tensor representing the graph's adjacency matrix
  - `degree_sequence` - List of vertices ordered by their processing sequence
  - `orphan_communities` - List of isolated vertices removed from the main computation

  ## Supported Input Formats

  ### Edge Lists
  ```elixir
  # Unweighted edges
  edges = [{:a, :b}, {:b, :c}, {:a, :c}]
  Source.build!(edges)

  # Weighted edges
  weighted_edges = [{:a, :b, 2}, {:b, :c, 3}, {:a, :c, 1}]
  Source.build!(weighted_edges)
  ```

  ### 2D Array Adjacency Matrices
  ```elixir
  matrix = [
    [0, 1, 1],
    [1, 0, 1],
    [1, 1, 0]
  ]
  Source.build!(matrix)
  ```

  ### Vertices and Edges Tuple
  ```elixir
  vertices = [:a, :b, :c]
  edges = [{:a, :b}, {:b, :c}]
  Source.build!({vertices, edges})
  ```

  ### Nx Tensor Adjacency Matrices
  ```elixir
  tensor = Nx.tensor([[0, 1, 0], [1, 0, 1], [0, 1, 0]])
  Source.build!(tensor)
  ```

  ### Graph Structs (libgraph)
  ```elixir
  graph = Graph.new(type: :undirected)
          |> Graph.add_edge(:a, :b, weight: 2)
          |> Graph.add_edge(:b, :c, weight: 3)
  Source.build!(graph)
  ```
  """
  alias ExLeiden.Utils

  defmodule Behaviour do
    @callback build!(term()) :: ExLeiden.Source.t()
  end

  @behaviour Behaviour

  @type community :: any()
  @type t :: %__MODULE__{
          adjacency_matrix: nil | Nx.Tensor.t(),
          orphan_communities: [community()],
          degree_sequence: [community()]
        }

  defstruct adjacency_matrix: nil,
            orphan_communities: [],
            degree_sequence: []

  @impl true
  def build!(%Nx.Tensor{} = matrix) do
    if is_adjacency_matrix?(matrix) do
      vertex_count = matrix |> Nx.shape() |> elem(0)
      orphans = orphans(matrix)
      degree_sequence = (0 |> Range.new(vertex_count - 1) |> Enum.to_list()) -- orphans

      %__MODULE__{
        adjacency_matrix: remove_orphans(matrix, degree_sequence),
        orphan_communities: orphans,
        degree_sequence: degree_sequence
      }
    else
      raise ArgumentError, "It's not a valid adjacency matrix"
    end
  end

  def build!([edge | _] = edges) when is_tuple(edge) do
    # Use MapSet for O(1) vertex collection instead of flat_map + uniq
    vertices =
      edges
      |> Enum.reduce(MapSet.new(), fn
        {v1, v2}, acc -> acc |> MapSet.put(v1) |> MapSet.put(v2)
        {v1, v2, _}, acc -> acc |> MapSet.put(v1) |> MapSet.put(v2)
      end)
      |> MapSet.to_list()
      |> Enum.sort()

    # Create vertex-to-index map for O(1) lookups
    vertex_to_index = vertices |> Enum.with_index() |> Map.new()

    {indices, values} =
      Enum.reduce(edges, {[], []}, fn
        {vertex_1, vertex_2}, {index_acc, value_acc} ->
          index_1 = Map.fetch!(vertex_to_index, vertex_1)
          index_2 = Map.fetch!(vertex_to_index, vertex_2)

          {[[index_1, index_2], [index_2, index_1] | index_acc], [1, 1 | value_acc]}

        {vertex_1, vertex_2, weight}, {index_acc, value_acc} when is_number(weight) ->
          index_1 = Map.fetch!(vertex_to_index, vertex_1)
          index_2 = Map.fetch!(vertex_to_index, vertex_2)

          {[[index_1, index_2], [index_2, index_1] | index_acc], [weight, weight | value_acc]}
      end)

    initial_matrix =
      if indices == [] do
        Nx.broadcast(0, {length(vertices), length(vertices)})
      else
        0
        |> Nx.broadcast({length(vertices), length(vertices)})
        |> Nx.indexed_add(Nx.tensor(indices), Nx.tensor(values))
      end

    %{
      adjacency_matrix: matrix,
      orphan_communities: orphans,
      degree_sequence: degree_sequence
    } = build!(initial_matrix)

    %__MODULE__{
      adjacency_matrix: matrix,
      orphan_communities: Utils.take_by_indices(vertices, orphans),
      degree_sequence: Utils.take_by_indices(vertices, degree_sequence)
    }
  end

  def build!([[weight | _] | _] = matrix) when is_number(weight) do
    matrix
    |> Nx.tensor()
    |> build!()
  end

  def build!({vertices, edges}) when is_list(vertices) and is_list(edges) do
    # Create vertex-to-index map for O(1) lookups
    vertex_to_index = vertices |> Enum.with_index() |> Map.new()

    {indices, values} =
      Enum.reduce(edges, {[], []}, fn
        {vertex_1, vertex_2}, {index_acc, value_acc} = acc ->
          index_1 = Map.get(vertex_to_index, vertex_1)
          index_2 = Map.get(vertex_to_index, vertex_2)

          if is_nil(index_1) or is_nil(index_2) do
            acc
          else
            {[[index_1, index_2], [index_2, index_1] | index_acc], [1, 1 | value_acc]}
          end

        {vertex_1, vertex_2, weight}, {index_acc, value_acc} = acc when is_number(weight) ->
          index_1 = Map.get(vertex_to_index, vertex_1)
          index_2 = Map.get(vertex_to_index, vertex_2)

          if is_nil(index_1) or is_nil(index_2) do
            acc
          else
            {[[index_1, index_2], [index_2, index_1] | index_acc], [weight, weight | value_acc]}
          end
      end)

    initial_matrix =
      if indices == [] do
        Nx.broadcast(0, {length(vertices), length(vertices)})
      else
        0
        |> Nx.broadcast({length(vertices), length(vertices)})
        |> Nx.indexed_add(Nx.tensor(indices), Nx.tensor(values))
      end

    %{
      adjacency_matrix: matrix,
      orphan_communities: orphans,
      degree_sequence: degree_sequence
    } = build!(initial_matrix)

    %__MODULE__{
      adjacency_matrix: matrix,
      orphan_communities: Utils.take_by_indices(vertices, orphans),
      degree_sequence: Utils.take_by_indices(vertices, degree_sequence)
    }
  end

  def build!(%Graph{type: :undirected} = graph) do
    vertices = Graph.vertices(graph)

    edges =
      graph
      |> Graph.edges()
      |> Enum.map(fn %{v1: v1, v2: v2, weight: weight} ->
        {v1, v2, weight}
      end)

    build!({vertices, edges})
  end

  def build!(_), do: raise(ArgumentError, "The graph should be the undirected or bi-directed")

  defp is_adjacency_matrix?(matrix) do
    cond do
      is_not_square_matrix?(matrix) -> false
      is_not_zero_diagonal?(matrix) -> false
      are_not_all_finity_numbers?(matrix) -> false
      is_not_symmetric?(matrix) -> false
      has_neg_numbers?(matrix) -> false
      true -> true
    end
  end

  defp is_not_square_matrix?(matrix) do
    case Nx.shape(matrix) do
      {count, count} -> false
      _ -> true
    end
  end

  defp is_not_zero_diagonal?(matrix) do
    result = check_zero_diagonal(matrix)
    Nx.to_number(result) == 0
  end

  defnp check_zero_diagonal(matrix) do
    matrix
    |> Nx.take_diagonal()
    |> Nx.equal(0)
    |> Nx.all()
  end

  defp are_not_all_finity_numbers?(matrix) do
    result = check_finite_numbers(matrix)
    Nx.to_number(result) == 1
  end

  defnp check_finite_numbers(matrix) do
    has_inf = matrix |> Nx.is_infinity() |> Nx.any()
    has_nan = matrix |> Nx.is_nan() |> Nx.any()
    Nx.logical_or(has_inf, has_nan)
  end

  defp has_neg_numbers?(matrix) do
    result = check_negative_numbers(matrix)
    Nx.to_number(result) == 1
  end

  defnp check_negative_numbers(matrix) do
    Nx.less(matrix, 0) |> Nx.any()
  end

  defp is_not_symmetric?(matrix) do
    result = check_symmetric(matrix)
    Nx.to_number(result) == 0
  end

  defnp check_symmetric(matrix) do
    Nx.all_close(Nx.transpose(matrix), matrix)
  end

  defp orphans(matrix) do
    orphan_mask = find_orphan_mask(matrix)

    orphan_mask
    |> Nx.to_flat_list()
    |> Enum.with_index()
    |> Enum.filter(fn {is_orphan, _index} -> is_orphan == 1 end)
    |> Enum.map(fn {_is_orphan, index} -> index end)
  end

  defnp find_orphan_mask(matrix) do
    matrix
    |> Nx.sum(axes: [0])
    |> Nx.equal(0)
  end

  defp remove_orphans(matrix, []), do: matrix

  defp remove_orphans(matrix, kept_index) do
    kept_index_tensor = Nx.tensor(kept_index)
    remove_orphans_defn(matrix, kept_index_tensor)
  end

  defnp remove_orphans_defn(matrix, kept_index_tensor) do
    matrix
    |> Nx.take(kept_index_tensor, axis: 0)
    |> Nx.take(kept_index_tensor, axis: 1)
  end
end
