import
  std/typetraits,
  stew/shims/macros, faststreams/[inputs, outputs],
  ./serialization/[object_serialization, errors, formats]

export
  inputs, outputs, object_serialization, errors, formats

template encode*(Format: type, value: auto, params: varargs[untyped]): auto =
  mixin init, Writer, writeValue, PreferredOutputType
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
      raise (ref Defect)() # a memoryOutput cannot have an IOError

# TODO Nim cannot make sense of this initialization by var param?
{.push warning[ProveInit]: off.}
proc readValue*(reader: var auto, T: type): T =
  mixin readValue
  when (NimMajor, NimMinor) > (1, 6):
    result = default(T)
  reader.readValue(result)
{.pop.}

template decode*(Format: distinct type,
                 input: string,
                 RecordType: distinct type,
                 params: varargs[untyped]): auto =
  # TODO, this is dusplicated only due to a Nim bug:
  # If `input` was `string|openArray[byte]`, it won't match `seq[byte]`
  mixin init, Reader
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
      raise (ref Defect)() # memory inputs cannot raise an IOError

template decode*(Format: distinct type,
                 input: openArray[byte],
                 RecordType: distinct type,
                 params: varargs[untyped]): auto =
  # TODO, this is dusplicated only due to a Nim bug:
  # If `input` was `string|openArray[byte]`, it won't match `seq[byte]`
  mixin init, Reader
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
      raise (ref Defect)() # memory inputs cannot raise an IOError

template loadFile*(Format: distinct type,
                   filename: string,
                   RecordType: distinct type,
                   params: varargs[untyped]): auto =
  mixin init, Reader, readValue

  var stream = memFileInput(filename)
  try:
    type ReaderType = Reader(Format)
    var reader = unpackArgs(init, [ReaderType, stream, params])
    reader.readValue(RecordType)
  finally:
    close stream

template loadFile*[RecordType](Format: type,
                               filename: string,
                               record: var RecordType,
                               params: varargs[untyped]) =
  record = loadFile(Format, filename, RecordType, params)

template saveFile*(Format: type, filename: string, value: auto, params: varargs[untyped]) =
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

  proc writeValue*[Writer](writer: var Writer, value: Alias) =
    mixin writeValue
    writeValue(writer, distinctBase value)

  proc readValue*[Reader](reader: var Reader, value: var Alias) =
    mixin readValue
    value = Alias reader.readValue(distinctBase Alias)

template borrowSerialization*(Alias: distinct type,
                              OriginalType: distinct type) {.dirty.} =

  proc writeValue*[Writer](writer: var Writer, value: Alias) =
    mixin writeValue
    writeValue(writer, OriginalType value)

  proc readValue*[Reader](reader: var Reader, value: var Alias) =
    mixin readValue
    value = Alias reader.readValue(OriginalType)

template serializesAsBase*(SerializedType: distinct type,
                           Format: distinct type) =
  mixin Reader, Writer

  type ReaderType = Reader(Format)
  type WriterType = Writer(Format)

  template writeValue*(writer: var WriterType, value: SerializedType) =
    mixin writeValue
    writeValue(writer, distinctBase value)

  template readValue*(reader: var ReaderType, value: var SerializedType) =
    mixin readValue
    value = SerializedType reader.readValue(distinctBase SerializedType)

macro serializesAsBaseIn*(SerializedType: type,
                          Formats: varargs[untyped]) =
  result = newStmtList()
  for Fmt in Formats:
    result.add newCall(bindSym"serializesAsBase", SerializedType, Fmt)

template readValue*(stream: InputStream,
                    Format: type,
                    ValueType: type,
                    params: varargs[untyped]): untyped =
  mixin Reader, init, readValue
  type ReaderType = Reader(Format)
  var reader = unpackArgs(init, [ReaderType, stream, params])
  readValue reader, ValueType

template writeValue*(stream: OutputStream,
                     Format: type,
                     value: auto,
                     params: varargs[untyped]) =
  mixin Writer, init, writeValue
  type WriterType = Writer(Format)
  var writer = unpackArgs(init, [WriterType, stream, params])
  writeValue writer, value

