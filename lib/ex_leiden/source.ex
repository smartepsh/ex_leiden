defmodule ExLeiden.Source do
  @moduledoc """
  Internal representation of graph data for the Leiden algorithm.

  Converts various input formats into a standardized adjacency matrix representation, using Nx tensors for efficient numerical computation.
  """

  @type community :: any()
  @type t :: %__MODULE__{
          adjacency_matrix: nil | Nx.Tensor.t(),
          orphan_communities: [community()],
          degree_sequence: [community()]
        }

  defstruct adjacency_matrix: nil,
            orphan_communities: [],
            degree_sequence: []

  alias ExLeiden.Utils

  @spec build!(term()) :: t()
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

    %{
      adjacency_matrix: matrix,
      orphan_communities: orphans,
      degree_sequence: degree_sequence
    } =
      0
      |> Nx.broadcast({length(vertices), length(vertices)})
      |> Nx.indexed_add(Nx.tensor(indices), Nx.tensor(values))
      |> build!()

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

    %{
      adjacency_matrix: matrix,
      orphan_communities: orphans,
      degree_sequence: degree_sequence
    } =
      0
      |> Nx.broadcast({length(vertices), length(vertices)})
      |> Nx.indexed_add(Nx.tensor(indices), Nx.tensor(values))
      |> build!()

    %__MODULE__{
      adjacency_matrix: matrix,
      orphan_communities: Utils.take_by_indices(vertices, orphans),
      degree_sequence: Utils.take_by_indices(vertices, degree_sequence)
    }
  end
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
    matrix
    |> Nx.take_diagonal()
    |> Nx.equal(0)
    |> Nx.all()
    |> Nx.to_number()
    |> Kernel.==(0)
  end

  defp are_not_all_finity_numbers?(matrix) do
    has_inf? = matrix |> Nx.is_infinity() |> Nx.any() |> Nx.to_number() |> Kernel.==(1)
    has_nan? = matrix |> Nx.is_nan() |> Nx.any() |> Nx.to_number() |> Kernel.==(1)

    has_inf? or has_nan?
  end

  defp has_neg_numbers?(matrix) do
    matrix |> Nx.less(0) |> Nx.any() |> Nx.to_number() |> Kernel.==(1)
  end

  defp is_not_symmetric?(matrix) do
    matrix |> Nx.transpose() |> Nx.all_close(matrix) |> Nx.to_number() |> Kernel.==(0)
  end

  defp orphans(matrix) do
    # Because this is a adjacency matrix, So, just verify with one of rows OR columns
    matrix
    |> Nx.sum(axes: [0])
    |> Nx.equal(0)
    |> Nx.to_list()
    |> Enum.with_index(0)
    |> Enum.filter(fn {is_orphan, _index} -> is_orphan == 1 end)
    |> Enum.map(fn {_is_orphan, index} -> index end)
  end

  defp remove_orphans(matrix, kept_index) do
    kept_index = Nx.tensor(kept_index)

    matrix
    |> Nx.take(kept_index, axis: 0)
    |> Nx.take(kept_index, axis: 1)
  end
end
