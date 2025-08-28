defmodule ExLeiden.Utils do
  def take_by_indices(list, indices) when is_list(list) and is_list(indices) do
    indices = MapSet.new(indices)

    list
    |> Enum.with_index()
    |> Enum.filter(fn {_value, index} -> index in indices end)
    |> Enum.map(fn {value, _} -> value end)
  end

  defmacro module(key) do
    quote do
      :ex_leiden
      |> Application.compile_env!(:mocks)
      |> Keyword.fetch!(unquote(key))
    end
  end
end
