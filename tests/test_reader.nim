import
  unittest2,
  ../serialization,
  ./otherencode

{.used.}

type
  TestObj = object
    number: int

  XyzReader = object

proc readValue(r: XyzReader, val: var TestObj) =
  val.number = 13

proc init(T: type XyzReader, stream: InputStream): T =
  XyzReader()

serializationFormat Xyz
Xyz.setReader XyzReader

suite "object serialization":
  test "readValue":
    let z = Xyz.decode("", TestObj)
    check z.number == 13

    var r: XyzReader
    let x = r.readValue(TestObj)
    check x.number == 13

# Make sure we don't encroach on other uses of "encode"
discard Base64Pad.encode(@[byte 1, 2 ,3])
