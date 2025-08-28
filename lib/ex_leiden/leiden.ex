defmodule ExLeiden.Leiden do
  alias ExLeiden.Source

  defmodule Behaviour do
    @callback call(Source.t(), keyword()) :: any()
  end

  @behaviour Behaviour

  @impl true
  def call(%Source{}, _opts) do
    :any
  end
end
