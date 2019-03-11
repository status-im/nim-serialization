type
  SerializationError* = object of CatchableError
  UnexpectedEofError* = object of SerializationError

