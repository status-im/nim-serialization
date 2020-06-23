import
  typetraits,
  stew/shims/macros, faststreams,
  serialization/[object_serialization, errors]

export
  faststreams, object_serialization, errors

template serializationFormatImpl(Name: untyped,
                                 Reader, Writer, PreferedOutput: distinct type,
                                 mimeTypeName: static string = "") {.dirty.} =
  # This indirection is required in order to be able to generate the
  # `mimeType` accessor template. Without the indirection, the template
  # mechanism of Nim will try to expand the `mimeType` param in the position
  # of the `mimeType` template name which will result in error.
  type Name* = object
  template ReaderType*(T: type Name): type = Reader
  template WriterType*(T: type Name): type = Writer
  template PreferedOutputType*(T: type Name): type = PreferedOutput
  template mimeType*(T: type Name): string = mimeTypeName

template serializationFormat*(Name: untyped,
                              Reader, Writer, PreferedOutput: distinct type,
                              mimeType: static string = "") =
  serializationFormatImpl(Name, Reader, Writer, PreferedOutput, mimeType)

template encode*(Format: type, value: auto, params: varargs[untyped]): auto =
  mixin init, WriterType, writeValue, PreferedOutputType
  {.noSideEffect.}:
    # We assume that there is no side-effects here, because we are
    # using a `memoryOutput`. The computed side-effects are coming
    # from the fact that the dynamic dispatch mechanisms used in
    # faststreams may be writing to a file or a network device.
    try:
      var s = memoryOutput()
      var writer = unpackArgs(init, [WriterType(Format), s, params])
      writeValue writer, value
      s.getOutput PreferedOutputType(Format)
    except IOError:
      raise (ref Defect)() # a memoryOutput cannot have an IOError

# TODO Nim cannot make sense of this initialization by var param?
{.push warning[ProveInit]: off.}
proc readValue*(reader: var auto, T: type): T =
  mixin readValue
  reader.readValue(result)
{.pop.}

template decode*(Format: distinct type,
                 input: string,
                 RecordType: distinct type,
                 params: varargs[untyped]): auto =
  # TODO, this is dusplicated only due to a Nim bug:
  # If `input` was `string|openarray[byte]`, it won't match `seq[byte]`
  mixin init, ReaderType
  {.noSideEffect.}:
    # We assume that there are no side-effects here, because we are
    # using a `memoryInput`. The computed side-effects are coming
    # from the fact that the dynamic dispatch mechanisms used in
    # faststreams may be reading from a file or a network device.
    try:
      var stream = unsafeMemoryInput(input)
      var reader = unpackArgs(init, [ReaderType(Format), stream, params])
      reader.readValue(RecordType)
    except IOError:
      raise (ref Defect)() # memory inputs cannot raise an IOError

template decode*(Format: distinct type,
                 input: openarray[byte],
                 RecordType: distinct type,
                 params: varargs[untyped]): auto =
  # TODO, this is dusplicated only due to a Nim bug:
  # If `input` was `string|openarray[byte]`, it won't match `seq[byte]`
  mixin init, ReaderType
  {.noSideEffect.}:
    # We assume that there are no side-effects here, because we are
    # using a `memoryInput`. The computed side-effects are coming
    # from the fact that the dynamic dispatch mechanisms used in
    # faststreams may be reading from a file or a network device.
    try:
      var stream = unsafeMemoryInput(input)
      var reader = unpackArgs(init, [ReaderType(Format), stream, params])
      reader.readValue(RecordType)
    except IOError:
      raise (ref Defect)() # memory inputs cannot raise an IOError

template loadFile*(Format: distinct type,
                   filename: string,
                   RecordType: distinct type,
                   params: varargs[untyped]): auto =
  mixin init, ReaderType, readValue

  var stream = memFileInput(filename)
  try:
    var reader = unpackArgs(init, [ReaderType(Format), stream, params])
    reader.readValue(RecordType)
  finally:
    close stream

template loadFile*[RecordType](Format: type,
                               filename: string,
                               record: var RecordType,
                               params: varargs[untyped]) =
  record = loadFile(Format, filename, RecordType, params)

template saveFile*(Format: type, filename: string, value: auto, params: varargs[untyped]) =
  mixin init, WriterType, writeValue

  var stream = fileOutput(filename)
  try:
    var writer = unpackArgs(init, [WriterType(Format), stream, params])
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
  mixin ReaderType, WriterType

  type Reader = ReaderType(Format)
  type Writer = WriterType(Format)

  template writeValue*(writer: var Writer, value: SerializedType) =
    mixin writeValue
    writeValue(writer, distinctBase value)

  template readValue*(reader: var Reader, value: var SerializedType) =
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
  mixin ReaderType, init, readValue
  var reader = unpackArgs(init, [ReaderType(Format), stream, params])
  readValue reader, ValueType

template writeValue*(stream: OutputStream,
                     Format: type,
                     value: auto,
                     params: varargs[untyped]) =
  mixin WriterType, init, writeValue
  var writer = unpackArgs(init, [WriterType(Format), stream])
  writeValue writer, value

