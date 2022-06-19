type
  SerializationError* = object of CatchableError
  UnexpectedEofError* = object of SerializationError
  CustomSerializationError* = object of SerializationError

method formatMsg*(err: ref SerializationError, filename: string): string
                 {.gcsafe, base, raises: [Defect].} =
  "Serialisation error while processing " & filename & ":" & err.msg

