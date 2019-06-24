import
  unittest, times, typetraits,
  faststreams/input_stream,
  ../object_serialization

type
  Transaction = object
    amount: int
    time: DateTime
    sender: string
    receiver: string

  Foo = object
    x: uint64
    y: string
    z: seq[int]

  Bar = object
    b: string
    f: Foo

  # Baz should use custom serialization
  # The `i` field should be multiplied by two while deserialing and
  # `ignored` field should be set to 10
  Baz = object
    f: Foo
    i: int
    ignored {.dontSerialize.}: int

proc default(T: typedesc): T = discard

template roundtripTest*(Format: type, val: auto) =
  test Format.name & " " & val.type.name & " roundtrip":
    let v = val
    let serialized = Format.encode(v)
    check: Format.decode(serialized, v.type) == v

template roundtripTest*(Format: type, value: auto, expectedResult: auto) =
  test Format.name & " " & val.type.name & " roundtrip":
    let v = value
    let serialized = Format.encode(v)
    check:
      serialized = expectedResult
      Format.decode(serialized, v.type) == v

proc executeReaderWriterTests*(Format: type) =
  mixin init, ReaderType, WriterType

  type
    Reader = ReaderType Format
    Writer = WriterType Format

  suite(typetraits.name(Format) & " read/write tests"):
    test "Low-level field reader test":
      let barFields = fieldReadersTable(Bar, Reader)
      var idx = 0

      var fieldReader = findFieldReader(barFields[], "b", idx)
      check fieldReader != nil and idx == 1

      # check that the reader can be found again starting from a higher index
      fieldReader = findFieldReader(barFields[], "b", idx)
      check fieldReader != nil and idx == 1

      var bytes = Format.encode("test")
      var stream = memoryStream(bytes)
      var reader = Reader.init(stream)

      var bar: Bar
      fieldReader(bar, reader)

      check bar.b == "test"

    test "Ignored fields should not be included in the field readers table":
      var pos = 0
      let bazFields = fieldReadersTable(Baz, Reader)
      check:
        len(bazFields[]) == 2
        findFieldReader(bazFields[], "f", pos) != nil
        findFieldReader(bazFields[], "i", pos) != nil
        findFieldReader(bazFields[], "i", pos) != nil
        findFieldReader(bazFields[], "f", pos) != nil
        findFieldReader(bazFields[], "f", pos) != nil
        findFieldReader(bazFields[], "ignored", pos) == nil
        findFieldReader(bazFields[], "some_other_name", pos) == nil

    test "Encoding and decoding an object":
      var originalBar = Bar(b: "abracadabra",
                            f: Foo(x: 5'u64, y: "hocus pocus", z: @[100, 200, 300]))

      var bytes = Format.encode(originalBar)
      var s = memoryStream(bytes)
      var reader = Reader.init(s)
      var restoredBar = reader.readValue(Bar)

      check:
        originalBar == restoredBar

      when false:
        var t1 = Transaction(time: now(), amount: 1000, sender: "Alice", receiver: "Bob")
        bytes = Format.encode(t1)
        var t2 = Format.decode(bytes, Transaction)

        check:
          t2.time == default(DateTime)
          t2.sender == "Alice"
          t2.receiver == "Bob"
          t2.amount == 1000

        var origVal = Baz(f: Foo(x: 10'u64, y: "y", z: @[]), ignored: 5)
        bytes = Format.encode(origVal)
        var restored = Format.decode(bytes, Baz)

        check:
          origVal.f.x == restored.f.x
          origVal.f.i == restored.f.i div 2
          origVal.f.y.len == restored.f.y.len
          restored.ignored == 10

