import
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
    var s = memoryOutput()
    var writer = unpackArgs(init, [WriterType(Format), s, params])
    writeValue writer, value
    s.getOutput PreferedOutputType(Format)

proc readValue*(reader: var auto, T: type): T =
  mixin readValue
  reader.readValue(result)

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
    var stream = memoryInput(input)
    var reader = unpackArgs(init, [ReaderType(Format), stream, params])
    reader.readValue(RecordType)

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
    var stream = memoryInput(input)
    var reader = unpackArgs(init, [ReaderType(Format), stream, params])
    reader.readValue(RecordType)

template loadFile*(Format: distinct type,
                   filename: string,
                   RecordType: distinct type,
                   params: varargs[untyped]): auto =
  mixin init, ReaderType
  var stream = openFile(filename)
  try:
    # TODO:
    # Remove this when statement once the following bug is fixed:
    # https://github.com/nim-lang/Nim/issues/9996
    when astToStr(params) != "":
      var reader = init(ReaderType(Format), stream, params)
    else:
      var reader = init(ReaderType(Format), stream)

    reader.readValue(RecordType)
  finally:
    # TODO: destructors
    if not stream.isNil:
      stream[].close()

template loadFile*[RecordType](Format: type,
                               filename: string,
                               record: var RecordType,
                               params: varargs[untyped]) =
  record = loadFile(Format, filename, RecordType, params)

template saveFile*(Format: type, filename: string, args: varargs[untyped]) =
  when false:
    # TODO use faststreams output stream
    discard
  else:
    let bytes = Format.encode(args)
    writeFile(filename, cast[string](bytes))

template borrowSerialization*(Alias: distinct type,
                              OriginalType: distinct type) {.dirty.} =

  proc writeValue*[Writer](writer: var Writer, value: Alias) =
    mixin writeValue
    writeValue(writer, OriginalType value)

  proc readValue*[Reader](reader: var Reader, value: var Alias) =
    mixin readValue
    value = Alias reader.readValue(OriginalType)

template appendValue*(stream: OutputStream, Format: type, value: auto) =
  mixin WriterType, init, writeValue
  var writer = init(WriterType(Format), stream)
  writeValue writer, value

