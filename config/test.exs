import Config

# Override mocks configuration for test environment - append "Mock" to module names
config :ex_leiden, :mocks,
  leiden: ExLeiden.LeidenMock,
  option: ExLeiden.OptionMock,
  source: ExLeiden.SourceMock,
  local_move: ExLeiden.Leiden.LocalMoveMock,
  modularity_quality: ExLeiden.Quality.ModularityMock,
  cpm_quality: ExLeiden.Quality.CPMMock
