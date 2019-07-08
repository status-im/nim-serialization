type
  SerializationError* = object of CatchableError
  UnexpectedEofError* = object of SerializationError
  CustomSerializationError* = object of SerializationError

method formatMsg*(err: ref SerializationError, filename: string): string {.gcsafe, base.} =
  "Serialisation error while processing " & filename

