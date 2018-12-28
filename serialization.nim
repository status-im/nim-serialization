import
  faststreams, serialization/object_serialization

export
  faststreams, object_serialization

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

proc encodeImpl(writer: var auto, value: auto) =
  mixin writeValue, getOutput
  writer.writeValue value

template encode*(Format: type, value: auto, params: varargs[untyped]): auto =
  mixin init, WriterType, PreferedOutputType
  var s = init MemoryOutputStream[PreferedOutputType(Format)]

  # TODO:
  # Remove this when statement once the following bug is fixed:
  # https://github.com/nim-lang/Nim/issues/9996
  when astToStr(params) != "":
    var writer = init(WriterType(Format), addr s, params)
  else:
    var writer = init(WriterType(Format), addr s)

  encodeImpl(writer, value)
  s.getOutput

proc readValue*(reader: var auto, T: type): T =
  mixin readValue
  reader.readValue(result)

proc readValueFromStream(Format: distinct type,
                         stream: ByteStream,
                         RecordType: distinct type): RecordType =
  mixin init, ReaderType
  var reader = init(ReaderType(Format), stream)
  reader.readValue(RecordType)

template decode*(Format: distinct type,
                 input: openarray[byte] | string,
                 RecordType: distinct type): auto =
  var stream = memoryStream(input)
  readValueFromStream(Format, stream, RecordType)

template loadFile*(Format: distinct type,
                   filename: string,
                   RecordType: distinct type): auto =
  var stream = openFile(filename)
  readValueFromStream(Format, stream, RecordType)

template loadFile*[RecordType](Format: type,
                               filename: string,
                               record: var RecordType) =
  var stream = openFile(filename)
  record = readValueFromStream(Format, stream, type(record))

template saveFile*(Format: type, filename: string, args: varargs[untyped]) =
  # TODO: This should use a proper output stream, instead of calling `encode`
  writeFile(filename, Format.encode(args))

