# Setup Hammox for mocking
Hammox.defmock(ExLeiden.LeidenMock, for: ExLeiden.Leiden.Behaviour)
Hammox.defmock(ExLeiden.OptionMock, for: ExLeiden.Option.Behaviour)
Hammox.defmock(ExLeiden.SourceMock, for: ExLeiden.Source.Behaviour)
