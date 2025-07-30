import
  std/typetraits,
  stew/shims/macros,
  faststreams/[inputs, outputs],
  ./serialization/[object_serialization, errors, formats]

export inputs, outputs, object_serialization, errors, formats

template encode*(
    Format: type SerializationFormat, value: auto, params: varargs[untyped]
): auto =
  mixin init, Writer, writeValue, PreferredOutputType
  block: # https://github.com/nim-lang/Nim/issues/22874
    {.noSideEffect.}:
      # We assume that there is no side-effects here, because we are
      # using a `memoryOutput`. The computed side-effects are coming
      # from the fact that the dynamic dispatch mechanisms used in
      # faststreams may be writing to a file or a network device.
      try:
        var s = memoryOutput()
        type WriterType = Writer(Format)
        var writer = unpackArgs(init, [WriterType, s, params])
        writeValue writer, value
        s.getOutput PreferredOutputType(Format)
      except IOError:
        raiseAssert "memoryOutput doesn't raise IOError"

# TODO Nim cannot make sense of this initialization by var param?
proc readValue*(
    reader: var auto, T: type
): T {.gcsafe, raises: [SerializationError, IOError].} =
  {.warning[ProveInit]: false.}
  mixin readValue
  result = default(T)
  reader.readValue(result)
  {.warning[ProveInit]: true.}

template decodeImpl(
    Format: type SerializationFormat,
    input: auto,
    RecordType: type,
    params: varargs[untyped]): auto =
  mixin init, Reader
  block: # https://github.com/nim-lang/Nim/issues/22874
    {.noSideEffect.}:
      # We assume that there are no side-effects here, because we are
      # using a `memoryInput`. The computed side-effects are coming
      # from the fact that the dynamic dispatch mechanisms used in
      # faststreams may be reading from a file or a network device.
      try:
        var stream = unsafeMemoryInput(input)
        type ReaderType = Reader(Format)
        var reader = unpackArgs(init, [ReaderType, stream, params])
        reader.readValue(RecordType)
      except IOError:
        when not defined(gcDestructors):
          # TODO https://github.com/nim-lang/Nim/issues/25080
          # touch the input to avoid gc issues
          # conveniently, the exception handler must outlive the `reader`
          # This defect will never actually be raised so `msg` doesn't matter
          # but we want to keep the codegen relatively short since this is a
          # template
          raiseAssert(
            if input.len > 0: "memory input doesn't raise IOError"
            else: "memory input doesn't raise IOError 0"
          )
        else:
          raiseAssert "memory input doesn't raise IOError"

template decode*(
    Format: type SerializationFormat,
    input: string,
    RecordType: type,
    params: varargs[untyped]): auto =
  decodeImpl(Format, input, RecordType, params)

template decode*(
    Format: type SerializationFormat,
    input: openArray[char],
    RecordType: type,
    params: varargs[untyped]): auto =
  decodeImpl(Format, input, RecordType, params)

template decode*(
    Format: type SerializationFormat,
    input: openArray[byte],
    RecordType: type,
    params: varargs[untyped]): auto =
  # TODO, this is duplicated only due to a Nim bug:
  # If `input` was `string|openArray[byte]`, it won't match `seq[byte]`
  decodeImpl(Format, input, RecordType, params)

template loadFile*(
    Format: type SerializationFormat,
    filename: string,
    RecordType: type,
    params: varargs[untyped],
): auto =
  mixin init, Reader, readValue

  var stream = memFileInput(filename)
  try:
    type ReaderType = Reader(Format)
    var reader = unpackArgs(init, [ReaderType, stream, params])
    reader.readValue(RecordType)
  finally:
    close stream

template loadFile*[RecordType](
    Format: type SerializationFormat,
    filename: string,
    record: var RecordType,
    params: varargs[untyped],
) =
  record = loadFile(Format, filename, RecordType, params)

template saveFile*(
    Format: type SerializationFormat,
    filename: string,
    value: auto,
    params: varargs[untyped],
) =
  mixin init, Writer, writeValue

  var stream = fileOutput(filename)
  try:
    type WriterType = Writer(Format)
    var writer = unpackArgs(init, [WriterType, stream, params])
    writer.writeValue(value)
  finally:
    close stream

template borrowSerialization*(Alias: type) {.dirty.} =
  bind distinctBase

  proc writeValue*[Writer](writer: var Writer, value: Alias) {.raises: [IOError].} =
    mixin writeValue
    writeValue(writer, distinctBase value)

  proc readValue*[Reader](reader: var Reader, value: var Alias) =
    mixin readValue
    value = Alias reader.readValue(distinctBase Alias)

template borrowSerialization*(Alias: type, OriginalType: type) {.dirty.} =
  proc writeValue*[Writer](writer: var Writer, value: Alias) {.raises: [IOError].} =
    mixin writeValue
    writeValue(writer, OriginalType value)

  proc readValue*[Reader](reader: var Reader, value: var Alias) =
    mixin readValue
    value = Alias reader.readValue(OriginalType)

template serializesAsBase*(SerializedType: type, Format: type SerializationFormat) =
  mixin Reader, Writer

  type ReaderType = Reader(Format)
  type WriterType = Writer(Format)

  template writeValue*(writer: var WriterType, value: SerializedType) =
    mixin writeValue
    writeValue(writer, distinctBase value)

  template readValue*(reader: var ReaderType, value: var SerializedType) =
    mixin readValue
    value = SerializedType reader.readValue(distinctBase SerializedType)

macro serializesAsBaseIn*(SerializedType: type, Formats: varargs[untyped]) =
  result = newStmtList()
  for Fmt in Formats:
    result.add newCall(bindSym"serializesAsBase", SerializedType, Fmt)

template readValue*(
    stream: InputStream,
    Format: type SerializationFormat,
    ValueType: type,
    params: varargs[untyped],
): untyped =
  mixin Reader, init, readValue
  type ReaderType = Reader(Format)
  var reader = unpackArgs(init, [ReaderType, stream, params])
  readValue reader, ValueType

template writeValue*(
    stream: OutputStream,
    Format: type SerializationFormat,
    value: auto,
    params: varargs[untyped],
) =
  mixin Writer, init, writeValue
  type WriterType = Writer(Format)
  var writer = unpackArgs(init, [WriterType, stream, params])
  writeValue writer, value
