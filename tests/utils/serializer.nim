## This is a simple serializer for testing purposes.
## It serializes to a binary format of:
## - for primitive types: <type, val.uint64.toBytes>
## - for seq, string: <type, val.len, val.toBytes>
## - for object, tuple: <type, val.len, recurse(val)>
## where type is an enum of the supported types
## where val.len is written as val.len.uint64.toBytes

{.push raises: [], gcsafe.}

import
  std/strutils,
  stew/endians2,
  ../../serialization

# XXX: export parseInt or bind it
#      required for write tuple
export serialization, parseInt

# XXX push raises

serializationFormat Ser

type SerWriter*[Flavor = DefaultFlavor] = object
  stream*: OutputStream

Ser.setWriter SerWriter, PreferredOutput = seq[byte]

func init*(W: type SerWriter, stream: OutputStream): W =
  W(stream: stream)

type SerReader* = object
  stream*: InputStream

Ser.setReader SerReader

func init*(R: type SerReader, stream: InputStream): R =
  R(stream: stream)

type SerKind* {.pure.} = enum
  Int = 0
  Float
  String
  Array
  Map
  Bool
  Nil

proc writeHead*(w: var SerWriter, k: SerKind, size: uint64) {.raises: [IOError].} =
  w.stream.write(k.ord.byte)
  w.stream.write(size.toBytesBE())

proc writeValue*(w: var SerWriter, val: auto) {.raises: [IOError].} =
  type T = typeof(val)
  when T is SomeInteger:
    writeHead(w, SerKind.Int, cast[uint64](val))
  elif T is SomeFloat:
    writeHead(w, SerKind.Float, cast[uint64](float64(val)))
  elif T is string:
    writeHead(w, SerKind.String, val.len.uint64)
    for x in val:
      w.stream.write x.byte
  elif T is seq:
    writeHead(w, SerKind.Array, val.len.uint64)
    for x in val:
      writeValue(w, x)
  elif T is (object or tuple):
    var L = 0
    val.enumInstanceSerializedFields(fieldName, fieldValue):
      inc L
      discard fieldName
      discard fieldValue
    writeHead(w, SerKind.Map, L.uint64)
    val.enumInstanceSerializedFields(fieldName, fieldValue):
      writeValue(w, fieldName)
      writeValue(w, fieldValue)
  elif T is bool:
    writeHead(w, SerKind.Bool, uint64(val))
  elif T is enum:
    writeHead(w, SerKind.Int, uint64(val.ord))
  elif T is ref:
    if val.isNil:
      writeHead(w, SerKind.Nil, 0)
    else:
      writeValue(w, val[])
  else:
    {.error: "cannot write type " & $T.}

func allocPtr[T](p: var ref T) =
  p = new(T)

proc read(r: var SerReader): byte {.raises: [IOError, SerializationError].} =
  if not r.stream.readable():
    raise newException(SerializationError, "eof")
  r.stream.read()

proc peek(r: var SerReader): byte {.raises: [IOError, SerializationError].} =
  if not r.stream.readable():
    raise newException(SerializationError, "eof")
  r.stream.peek()

proc readUint64*(r: var SerReader): uint64 {.raises: [IOError, SerializationError].} =
  result = 0
  for _ in 0 ..< sizeof(uint64):
    result = (result shl 8) or r.read()

proc consumeKind*(r: var SerReader, k: SerKind) {.raises: [IOError, SerializationError].} =
  let ek = r.read()
  if ek.int != k.ord:
    raise newException(
      SerializationError, "expected " & $k.ord & "found " & $ek
    )

proc readValue*(r: var SerReader, val: var auto) {.raises: [IOError, SerializationError].} =
  type T = typeof(val)
  when T is SomeInteger:
    consumeKind r, SerKind.Int
    val = cast[T](r.readUint64())
  elif T is SomeFloat:
    consumeKind r, SerKind.Float
    when T is float32:
      val = cast[float64](r.readUint64()).float32
    else:
      val = cast[T](r.readUint64())
  elif T is string:
    consumeKind r, SerKind.String
    for _ in 0 ..< r.readUint64():
      val.add r.read().char
  elif T is seq:
    consumeKind r, SerKind.Array
    for _ in 0 ..< r.readUint64():
      let lastPos = val.len
      val.setLen(lastPos + 1)
      readValue(r, val[lastPos])
  elif T is (object or tuple):
    consumeKind r, SerKind.Map
    type ReaderType = typeof(r)
    const fieldsTable = T.fieldReadersTable(ReaderType)
    var mostLikelyNextField = 0
    for _ in 0 ..< r.readUint64():
      let key = readValue(r, string)
      when T is tuple:
        let fieldIdx = mostLikelyNextField
        inc mostLikelyNextField
        discard key
      else:
        let fieldIdx = findFieldIdx(fieldsTable, key, mostLikelyNextField)
      if fieldIdx != -1:
        let reader = fieldsTable[fieldIdx].reader
        reader(val, r)
  elif T is bool:
    consumeKind r, SerKind.Bool
    val = T(r.readUint64())
  elif T is enum:
    consumeKind r, SerKind.Int
    val = T(r.readUint64())
  elif T is ref:
    if r.peek() == SerKind.Nil.ord:
      consumeKind r, SerKind.Nil
      val = nil
    else:
      allocPtr val
      readValue(r, val[])
  else:
    {.error: "cannot read type " & $T.}

iterator readObjectFields*(r: var SerReader): string {.raises: [IOError, SerializationError].} =
  consumeKind r, SerKind.Map
  for _ in 0 ..< r.readUint64():
    yield readValue(r, string)
