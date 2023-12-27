import
  std/[typetraits, macros]

type
  DefaultFlavor* = object

template serializationFormatImpl(Name: untyped,
                                 mimeTypeName: static string = "") {.dirty.} =
  # This indirection is required in order to be able to generate the
  # `mimeType` accessor template. Without the indirection, the template
  # mechanism of Nim will try to expand the `mimeType` param in the position
  # of the `mimeType` template name which will result in error.
  type Name* = object
  template mimeType*(T: type Name): string = mimeTypeName

template serializationFormat*(Name: untyped, mimeType: static string = "") =
  serializationFormatImpl(Name, mimeType)

template setReader*(Format, FormatReader: distinct type) =
  when arity(FormatReader) > 1:
    template ReaderType*(T: type Format, F: distinct type = DefaultFlavor): type = FormatReader[F]
    template Reader*(T: type Format, F: distinct type = DefaultFlavor): type = FormatReader[F]
  else:
    template ReaderType*(T: type Format): type = FormatReader
    template Reader*(T: type Format): type = FormatReader

template setWriter*(Format, FormatWriter, PreferredOutput: distinct type) =
  when arity(FormatWriter) > 1:
    template WriterType*(T: type Format, F: distinct type = DefaultFlavor): type = FormatWriter[F]
    template Writer*(T: type Format, F: distinct type = DefaultFlavor): type = FormatWriter[F]
  else:
    template WriterType*(T: type Format): type = FormatWriter
    template Writer*(T: type Format): type = FormatWriter

  template PreferredOutputType*(T: type Format): type = PreferredOutput

template createFlavor*(ModifiedFormat, FlavorName: untyped) =
  type FlavorName* = object
  template Reader*(T: type FlavorName): type = Reader(ModifiedFormat, FlavorName)
  template Writer*(T: type FlavorName): type = Writer(ModifiedFormat, FlavorName)
  template PreferredOutputType*(T: type FlavorName): type = PreferredOutputType(ModifiedFormat)
  template mimeType*(T: type FlavorName): string = mimeType(ModifiedFormat)

template useDefaultSerializationIn*(T: untyped, Flavor: type) =
  mixin Reader, Writer

  template readValue*(r: var Reader(Flavor), value: var T) =
    mixin readRecordValue
    readRecordValue(r, value)

  template writeValue*(w: var Writer(Flavor), value: T) =
    mixin writeRecordValue
    writeRecordValue(w, value)

template useDefaultWriterIn*(T: untyped, Flavor: type) =
  mixin Writer

  template writeValue*(w: var Writer(Flavor), value: T) =
    mixin writeRecordValue
    writeRecordValue(w, value)

template useDefaultReaderIn*(T: untyped, Flavor: type) =
  mixin Reader

  template readValue*(r: var Reader(Flavor), value: var T) =
    mixin readRecordValue
    readRecordValue(r, value)

macro useDefaultSerializationFor*(Flavor: type, types: varargs[untyped])=
  result = newStmtList()

  for T in types:
    result.add newCall(bindSym "useDefaultSerializationIn", T, Flavor)

macro useDefaultWriterFor*(Flavor: type, types: varargs[untyped])=
  result = newStmtList()

  for T in types:
    result.add newCall(bindSym "useDefaultWriterIn", T, Flavor)

macro useDefaultReaderFor*(Flavor: type, types: varargs[untyped])=
  result = newStmtList()

  for T in types:
    result.add newCall(bindSym "useDefaultReaderIn", T, Flavor)

