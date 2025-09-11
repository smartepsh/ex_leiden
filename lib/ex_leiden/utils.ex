defmodule ExLeiden.Utils do
  def take_by_indices(list, indices) when is_list(list) and is_list(indices) do
    indices = MapSet.new(indices)

    list
    |> Enum.with_index()
    |> Enum.filter(fn {_value, index} -> index in indices end)
    |> Enum.map(fn {value, _} -> value end)
  end

  @default_modules [
    leiden: ExLeiden.Leiden,
    option: ExLeiden.Option,
    source: ExLeiden.Source,
    local_move: ExLeiden.Leiden.LocalMove,
    refine_partition: ExLeiden.Leiden.RefinePartition,
    aggregate: ExLeiden.Leiden.Aggregate,
    modularity_quality: ExLeiden.Quality.Modularity,
    cpm_quality: ExLeiden.Quality.CPM
  ]

  def module(key) do
    :ex_leiden
    |> Application.get_env(:mocks, [])
    |> Keyword.get(key, @default_modules[key])
  end
end
