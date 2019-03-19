type
  SerializationError* = object of CatchableError
  UnexpectedEofError* = object of SerializationError

method formatMsg*(err: ref SerializationError, filename: string): string {.base.} =
  "Serialisation error while processing " & filename

