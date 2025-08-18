defmodule ExLeiden.Option do
  @moduledoc """
  Option validation for ExLeiden algorithm.
  """

  @type options :: %{
          resolution: number(),
          quality_function: :modularity | :cpm,
          max_level: pos_integer(),
          format: :graph | :communities_and_bridges
        }

  @default_opts %{
    resolution: 1,
    quality_function: :modularity,
    max_level: 5,
    format: :communities_and_bridges
  }

  @doc """
  Validates and applies options from a keyword list or map.

  Returns `{:ok, validated_options}` on success or `{:error, errors}` on validation failure.

  ## Examples

      iex> ExLeiden.Option.validate_opts([])
      {:ok, %{resolution: 1, quality_function: :modularity, max_level: 5, format: :communities_and_bridges}}

      iex> ExLeiden.Option.validate_opts(%{resolution: 2.5, quality_function: :cpm})
      {:ok, %{resolution: 2.5, quality_function: :cpm, max_level: 5, format: :communities_and_bridges}}

      iex> ExLeiden.Option.validate_opts(%{format: :graph})
      {:ok, %{resolution: 1, quality_function: :modularity, max_level: 5, format: :graph}}

      iex> ExLeiden.Option.validate_opts(%{resolution: -1.0})
      {:error, %{resolution: "must be a positive number"}}

      iex> ExLeiden.Option.validate_opts(%{max_level: 0, quality_function: :invalid})
      {:error, %{max_level: "must be a positive integer", quality_function: "must be :modularity or :cpm"}}

      iex> ExLeiden.Option.validate_opts(%{format: :invalid})
      {:error, %{format: "must be :graph or :communities_and_bridges"}}

  """
  @spec validate_opts(map | keyword) :: {:ok, options()} | {:error, map}
  def validate_opts(opts) when is_list(opts) do
    opts
    |> Map.new()
    |> validate_opts()
  end

  def validate_opts(opts) when is_map(opts) do
    opt_tuples =
      Enum.map(@default_opts, fn {key, default_value} ->
        case Map.get(opts, key) do
          nil ->
            {:ok, {key, default_value}}

          value ->
            case validate_option(key, value) do
              :ok -> {:ok, {key, value}}
              {:error, reason} -> {:error, {key, reason}}
            end
        end
      end)

    if Enum.all?(opt_tuples, &match?({:ok, _}, &1)) do
      {:ok, Map.new(opt_tuples, &elem(&1, 1))}
    else
      reason =
        opt_tuples
        |> Enum.filter(&match?({:error, _}, &1))
        |> Enum.map(&elem(&1, 1))
        |> Map.new()

      {:error, reason}
    end
  end

  defp validate_option(:resolution, value) when is_number(value) and value > 0 do
    :ok
  end

  defp validate_option(:resolution, _value) do
    {:error, "must be a positive number"}
  end

  defp validate_option(:max_level, value) when is_integer(value) and value > 0 do
    :ok
  end

  defp validate_option(:max_level, _value) do
    {:error, "must be a positive integer"}
  end

  defp validate_option(:quality_function, value) when value in [:modularity, :cpm] do
    :ok
  end

  defp validate_option(:quality_function, _value) do
    {:error, "must be :modularity or :cpm"}
  end

  defp validate_option(:format, value) when value in [:graph, :communities_and_bridges] do
    :ok
  end

  defp validate_option(:format, _value) do
    {:error, "must be :graph or :communities_and_bridges"}
  end
end
