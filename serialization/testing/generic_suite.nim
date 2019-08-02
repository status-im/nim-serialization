import
  unittest, times, typetraits, random, strutils, options, sets, tables,
  faststreams/input_stream,
  ../../serialization, ../object_serialization

type
  Meter* = distinct int
  Mile* = distinct int

  Simple* = object
    x*: int
    y*: string
    distance*: Meter
    ignored*: int

  Transaction* = object
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

  ListOfLists = object
    lists: seq[ListOfLists]

  # Baz should use custom serialization
  # The `i` field should be multiplied by two while deserializing and
  # `ignored` field should be set to 10
  Baz = object
    f: Foo
    i: int
    ignored {.dontSerialize.}: int

  NoExpectedResult = distinct int

  ObjectKind* = enum
    A
    B

  CaseObject* = object
   case kind: ObjectKind:
   of A:
     a*: int
     other*: CaseObjectRef
   else:
     b*: int

  CaseObjectRef* = ref CaseObject

  HoldsSet* = object
    a*: int
    s*: HashSet[string]

  HoldsOption* = object
    r*: ref Simple
    o*: Option[Simple]

  HoldsArray* = object
    data*: seq[int]

Meter.borrowSerialization int
Simple.setSerializedFields distance, x, y

proc default(T: typedesc): T = discard

func caseObjectEquals(a, b: CaseObject): bool

func `==`*(a, b: CaseObjectRef): bool =
  let nils = ord(a.isNil) + ord(b.isNil)
  if nils == 0:
    caseObjectEquals(a[], b[])
  else:
    nils == 2

func caseObjectEquals(a, b: CaseObject): bool =
  # TODO This is needed to work-around a Nim overload selection issue
  if a.kind != b.kind: return false

  case a.kind
  of A:
    if a.a != b.a: return false
    a.other == b.other
  of B:
    a.b == b.b

func `==`*(a, b: CaseObject): bool =
  caseObjectEquals(a, b)

template roundtripChecks*(Format: type, value: auto, expectedResult: auto) =
  let v = value
  let serialized = encode(Format, v)
  checkpoint "(encoded value): " & $serialized

  when not (expectedResult is NoExpectedResult):
    check serialized == expectedResult

  try:
    let decoded = Format.decode(serialized, type(v))
    checkpoint "(decoded value): " & repr(decoded)
    let decodedValueMatchesOriginal = decoded == v
    check decodedValueMatchesOriginal
  except SerializationError as err:
    checkpoint "(serialization error): " & err.formatMsg("(encoded value)")
    fail()

template roundtripTest*(Format: type, value: auto, expectedResult: auto) =
  mixin `==`
  # TODO can't use the dot operator on the next line.
  test name(Format) & " " & name(type(value)) & " roundtrip":
    roundtripChecks Format, value, expectedResult

template roundtripTest*(Format: type, value: auto) =
  roundtripTest(Format, value, NoExpectedResult(0))

template roundtripChecks*(Format: type, value: auto) =
  roundtripChecks(Format, value, NoExpectedResult(0))

proc executeRoundtripTests*(Format: type) =
  mixin init, ReaderType, WriterType

  type
    Reader = ReaderType Format
    Writer = WriterType Format

  template roundtrip(val: untyped) =
    mixin supports
    # TODO:
    # If this doesn't work reliably, it will fail too silently.
    # We need to report the number of checks passed.
    when supports(Format, type(val)):
      roundtripChecks(Format, val)

  suite(name(Format) & " generic roundtrip tests"):
    test "simple values":
      template intTests(T: untyped) =
        roundtrip low(T)
        roundtrip high(T)
        for i in 0..1000:
          roundtrip rand(low(T)..high(T))

      when false:
        intTests int8
        intTests int16
        intTests int32
        intTests int64
        intTests uint8
        intTests uint16
        intTests uint32
        intTests uint64

      roundtrip ""
      roundtrip "a"
      roundtrip repeat("a",1000)
      roundtrip repeat("a",100000)

      roundtrip @[1, 2, 3, 4]
      roundtrip newSeq[string]()
      roundtrip @["a", "", "b", "cd"]
      roundtrip @["", ""]

      roundtrip true
      roundtrip false

      roundtrip ObjectKind.A
      roundtrip ObjectKind.B

    test "objects":
      var b = Bar(b: "abracadabra",
                  f: Foo(x: 5'u64, y: "hocus pocus", z: @[100, 200, 300]))
      roundtrip b

      when false:
        # TODO: This requires the test suite of each format to implement
        # support for the DateTime type.
        var t = Transaction(time: now(), amount: 1000, sender: "Alice", receiver: "Bob")
        roundtrip t

      when false and supports(Format, Baz):
        # TODO: Specify the custom serialization required for the `Baz` type
        # and give it a more proper name. The custom serialization demands
        # that the `ignored` field is populated with a value depending on
        # the `i` value. `i` itself is doubled on deserialization.
        var origVal = Baz(f: Foo(x: 10'u64, y: "y", z: @[]), ignored: 5)
        bytes = Format.encode(origVal)
        var restored = Format.decode(bytes, Baz)

        check:
          origVal.f.x == restored.f.x
          origVal.f.i == restored.f.i div 2
          origVal.f.y.len == restored.f.y.len
          restored.ignored == 10

    test "case objects":
      var
        c1 = CaseObjectRef(kind: B, b: 100)
        c2 = CaseObjectRef(kind: A, a: 80, other: CaseObjectRef(kind: B))
        c3 = CaseObject(kind: A, a: 60, other: nil)

      roundtrip c1
      roundtrip c2
      roundtrip c3

    test "lists":
      var
        l1 = ListOfLists()
        l2 = ListOfLists(lists: @[])
        l3 = ListOfLists(lists: @[
              ListOfLists(lists: @[
                ListOfLists(),
                ListOfLists(),
              ]),
              ListOfLists(lists: @[
                ListOfLists(lists: @[ListOfLists()]),
                ListOfLists(lists: @[ListOfLists(lists: @[])])])
              ])

      roundtrip l1
      roundtrip l2
      roundtrip l3

    test "tables":
      var
        t1 = {"test": 0, "other": 1}.toTable()
        t2 = {"test": 0, "other": 1}.toOrderedTable()
        t3 = newTable[string, int]()

      t3["test"] = 0
      t3["other"] = 1

      roundtrip t1
      roundtrip t2
      roundtrip t3

    test "sets":
      var s1 = toSet([1, 2, 3, 1, 4, 2])
      var s2 = HoldsSet(a: 100, s: toSet(["a", "b", "c"]))

      roundtrip s1
      roundtrip s2

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

  executeRoundtripTests(Format)


