# Setup Hammox for mocking
Hammox.defmock(ExLeiden.LeidenMock, for: ExLeiden.Leiden.Behaviour)
Hammox.defmock(ExLeiden.OptionMock, for: ExLeiden.Option.Behaviour)
Hammox.defmock(ExLeiden.SourceMock, for: ExLeiden.Source.Behaviour)
Hammox.defmock(ExLeiden.Leiden.LocalMoveMock, for: ExLeiden.Leiden.LocalMove.Behaviour)

Hammox.defmock(ExLeiden.Leiden.RefinePartitionMock,
  for: ExLeiden.Leiden.RefinePartition.Behaviour
)

Hammox.defmock(ExLeiden.Leiden.AggregateMock, for: ExLeiden.Leiden.Aggregate.Behaviour)
Hammox.defmock(ExLeiden.Quality.ModularityMock, for: ExLeiden.Quality.Behaviour)
Hammox.defmock(ExLeiden.Quality.CPMMock, for: ExLeiden.Quality.Behaviour)
