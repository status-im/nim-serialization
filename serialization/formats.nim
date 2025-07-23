import
  std/[typetraits, macros]

type
  DefaultFlavor* = object

  SerializationFormat* {.inheritable, pure.} = object
    ## Marker type for serialization formats created with `serializationFormat`
    ## and `createFlavor`, for which encode/decoode and other serialization-based
    ## formats are supported

template serializationFormatImpl(Name: untyped,
                                 mimeTypeName: static string = "") {.dirty.} =
  # This indirection is required in order to be able to generate the
  # `mimeType` accessor template. Without the indirection, the template
  # mechanism of Nim will try to expand the `mimeType` param in the position
  # of the `mimeType` template name which will result in error.
  type Name* = object of SerializationFormat
  template mimeType*(T: type Name): string = mimeTypeName

template serializationFormat*(Name: untyped, mimeType: static string = "") =
  serializationFormatImpl(Name, mimeType)

template setReader*(Format: type SerializationFormat, FormatReader: distinct type) =
  when arity(FormatReader) > 1:
    template ReaderType*(T: type Format, F: distinct type = DefaultFlavor): type = FormatReader[F]
    template Reader*(T: type Format, F: distinct type = DefaultFlavor): type = FormatReader[F]
  else:
    template ReaderType*(T: type Format): type = FormatReader
    template Reader*(T: type Format): type = FormatReader

template setWriter*(Format: type SerializationFormat, FormatWriter, PreferredOutput: distinct type) =
  when arity(FormatWriter) > 1:
    template WriterType*(T: type Format, F: distinct type = DefaultFlavor): type = FormatWriter[F]
    template Writer*(T: type Format, F: distinct type = DefaultFlavor): type = FormatWriter[F]
  else:
    template WriterType*(T: type Format): type = FormatWriter
    template Writer*(T: type Format): type = FormatWriter

  template PreferredOutputType*(T: type Format): type = PreferredOutput

template createFlavor*(
    ModifiedFormat: type SerializationFormat,
    FlavorName: untyped,
    mimeTypeName: static string = ""
) =
  type FlavorName* = object of SerializationFormat
  template Reader*(T: type FlavorName): type = Reader(ModifiedFormat, FlavorName)
  template Writer*(T: type FlavorName): type = Writer(ModifiedFormat, FlavorName)
  template PreferredOutputType*(T: type FlavorName): type = PreferredOutputType(ModifiedFormat)
  template mimeType*(T: type FlavorName): string =
    when mimeTypeName == "":
      mimeType(ModifiedFormat)
    else:
      mimeTypeName

template toObjectType(T: type): untyped =
  typeof(T()[])

template toObjectTypeIfNecessary(T: type): untyped =
  when T is ref|ptr:
    toObjectType(T)
  else:
    T

# useDefault***In or useDefault***For only works for
# object|ref object|ptr object

template useDefaultSerializationIn*(T: untyped, Flavor: type) =
  mixin Reader, Writer

  type TT = toObjectTypeIfNecessary(T)

  template readValue*(r: var Reader(Flavor), value: var TT) =
    mixin readRecordValue
    readRecordValue(r, value)

  template writeValue*(w: var Writer(Flavor), value: TT) =
    mixin writeRecordValue
    writeRecordValue(w, value)

template useDefaultWriterIn*(T: untyped, Flavor: type) =
  mixin Writer

  type TT = toObjectTypeIfNecessary(T)

  template writeValue*(w: var Writer(Flavor), value: TT) =
    mixin writeRecordValue
    writeRecordValue(w, value)

template useDefaultReaderIn*(T: untyped, Flavor: type) =
  mixin Reader

  type TT = toObjectTypeIfNecessary(T)

  template readValue*(r: var Reader(Flavor), value: var TT) =
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
