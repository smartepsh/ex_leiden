import Config

# config :nx, :default_backend, EXLA.Backend
# config :nx, :default_defn_options, compiler: EXLA, client: :host

# Configuration for mocking modules during testing
config :ex_leiden, :mocks,
  leiden: ExLeiden.Leiden,
  option: ExLeiden.Option,
  source: ExLeiden.Source,
  local_move: ExLeiden.Leiden.LocalMove,
  refine_partition: ExLeiden.Leiden.RefinePartition,
  aggregate: ExLeiden.Leiden.Aggregate,
  modularity_quality: ExLeiden.Quality.Modularity,
  cpm_quality: ExLeiden.Quality.CPM

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
if "#{config_env()}.exs" |> Path.expand(__DIR__) |> File.exists?() do
  import_config "#{config_env()}.exs"
end
