import Config

# Configuration for mocking modules during testing
config :ex_leiden, :mocks,
  leiden: ExLeiden.Leiden,
  option: ExLeiden.Option,
  source: ExLeiden.Source,
  modularity_quality: ExLeiden.Quality.Modularity

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
if "#{config_env()}.exs" |> Path.expand(__DIR__) |> File.exists?() do
  import_config "#{config_env()}.exs"
end
