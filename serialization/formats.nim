import
  std/[typetraits, macros],
  ./flavor_auto_serialization

export
  flavor_auto_serialization

type
  DefaultFlavor* = object

  SerializationFormat* {.inheritable, pure.} = object
    ## Marker type for serialization formats created with `serializationFormat`
    ## and `createFlavor`, for which encode/decoode and other serialization-based
    ## formats are supported

template serializationFormatImpl(Name: untyped,
                                 mimeTypeName: static string = "",
                                 version: static uint = 0) {.dirty.} =
  # This indirection is required in order to be able to generate the
  # `mimeType` accessor template. Without the indirection, the template
  # mechanism of Nim will try to expand the `mimeType` param in the position
  # of the `mimeType` template name which will result in error.
  type Name* = object of SerializationFormat
  template mimeType*(T: type Name): string = mimeTypeName
  template versionInt*(T: type Name): uint = version

template serializationFormat*(Name: untyped,
                              mimeType: static string = "",
                              version: static uint = 0) =
  serializationFormatImpl(Name, mimeType, version)

# version behavior
# 0:
#   - Reader/Writer using DefaultFlavor
#   - SerializationFormat is the Flavor parent type
# 1:
#   - Reader/Writer using Format as default flavor
#   - Format is the Flavor parent type

template formatDefaultFlavor(Format: type): type =
  when Format.versionInt() == 0:
    DefaultFlavor
  else:
    Format

template formatFlavorParent(Format: type): type =
  when Format.versionInt() == 0:
    SerializationFormat
  else:
    Format

template setReader*(Format: type SerializationFormat, FormatReader: distinct type) =
  when arity(FormatReader) > 1:
    type Flavor = formatDefaultFlavor(Format)
    template ReaderType*(T: type Format, F: distinct type = Flavor): type = FormatReader[F]
    template Reader*(T: type Format, F: distinct type = Flavor): type = FormatReader[F]
  else:
    template ReaderType*(T: type Format): type = FormatReader
    template Reader*(T: type Format): type = FormatReader

template setWriter*(Format: type SerializationFormat, FormatWriter, PreferredOutput: distinct type) =
  when arity(FormatWriter) > 1:
    type Flavor = formatDefaultFlavor(Format)
    template WriterType*(T: type Format, F: distinct type = Flavor): type = FormatWriter[F]
    template Writer*(T: type Format, F: distinct type = Flavor): type = FormatWriter[F]
  else:
    template WriterType*(T: type Format): type = FormatWriter
    template Writer*(T: type Format): type = FormatWriter

  template PreferredOutputType*(T: type Format): type = PreferredOutput

template createFlavor*(
    ModifiedFormat: type SerializationFormat,
    FlavorName: untyped,
    mimeTypeName: static string = ""
) =
  type FlavorName* = object of formatFlavorParent(ModifiedFormat)
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
