import
  std/[times, typetraits, random, strutils, options, sets, tables],
  unittest2,
  faststreams/inputs,
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
    amount*: int
    time*: DateTime
    sender*: string
    receiver*: string

  BaseType* = object of RootObj
    a*: string
    b*: int

  BaseTypeRef* = ref BaseType

  DerivedType* = object of BaseType
    c*: int
    d*: string

  DerivedRefType* = ref object of BaseType
    c*: int
    d*: string

  DerivedFromRefType* = ref object of DerivedRefType
    e*: int

  RefTypeDerivedFromRoot* = ref object of RootObj
    a*: int
    b*: string

  Foo = object
    x*: uint64
    y*: string
    z*: seq[int]

  Bar = object
    b*: string
    f*: Foo

  # Baz should use custom serialization
  # The `i` field should be multiplied by two while deserializing and
  # `ignored` field should be set to 10
  Baz = object
    f*: Foo
    i*: int
    ignored* {.dontSerialize.}: int

  ListOfLists = object
    lists*: seq[ListOfLists]

  NoExpectedResult = distinct int

  ObjectKind* = enum
    A
    B

  CaseObject* = object
   case kind*: ObjectKind
   of A:
     a*: int
     other*: CaseObjectRef
   else:
     b*: int

  CaseObjectRef* = ref CaseObject

  HoldsCaseObject* = object
    value: CaseObject

  HoldsSet* = object
    a*: int
    s*: HashSet[string]

  HoldsOption* = object
    r*: ref Simple
    o*: Option[Simple]

  HoldsArray* = object
    data*: seq[int]

  AnonTuple* = (int, string, float64)

  AbcTuple* = tuple[a: int, b: string, c: float64]
  XyzTuple* = tuple[x: int, y: string, z: float64]

  HoldsTuples* = object
    t1*: AnonTuple
    t2*: AbcTuple
    t3*: XyzTuple

static:
  assert isCaseObject(CaseObject)
  assert isCaseObject(CaseObjectRef)

  assert(not isCaseObject(Transaction))
  assert(not isCaseObject(HoldsSet))

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

template maybeDefer(x: auto): auto =
  when type(x) is ref:
    x[]
  else:
    x

template roundtripChecks*(Format: type, value: auto, expectedResult: auto) =
  let origValue = value
  let serialized = encode(Format, origValue)
  checkpoint "(encoded value): " & $serialized

  when not (expectedResult is NoExpectedResult):
    check serialized == expectedResult

  try:
    let decoded = Format.decode(serialized, type(origValue))
    checkpoint "(decoded value): " & repr(decoded)
    let success = maybeDefer(decoded) == maybeDefer(origValue)
    check success

  except SerializationError as err:
    checkpoint "(serialization error): " & err.formatMsg("(encoded value)")
    fail()

  except:
    when compiles($value):
      checkpoint "unexpected failure in roundtrip test for " & $value
    raise

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
          roundtrip rand(T)

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

      when false and supports(Format, Transaction):
        # Some formats may not support the DateTime type.
        var t = Transaction(time: now(), amount: 1000, sender: "Alice", receiver: "Bob")
        roundtrip t

      when false and supports(Format, Baz):
        # TODO: Specify the custom serialization required for the `Baz` type
        # and give it a more proper name. The custom serialization demands
        # that the `ignored` field is populated with a value depending on
        # the `i` value. `i` itself is doubled on deserialization.
        let
          origVal = Baz(f: Foo(x: 10'u64, y: "y", z: @[]), ignored: 5)
          encoded = Format.encode(origVal)
          restored = Format.decode(encoded, Baz)

        check:
          origVal.f.x == restored.f.x
          origVal.f.y.len == restored.f.y.len
          origVal.i == restored.i div 2
          restored.ignored == 10

      block:
        let
          a = BaseType(a: "test", b: -1000)
          b = BaseTypeRef(a: "another test", b: 2000)
          c = RefTypeDerivedFromRoot(a: high(int), b: "")
          d = DerivedType(a: "a field", b: 1000, c: 10, d: "d field")
          e = DerivedRefType(a: "a field", b: -1000, c: 10, d: "")
          f = DerivedFromRefType(a: "a field", b: -1000, c: 10, d: "", e: 12)

        roundtrip a
        roundtrip b
        roundtrip c
        roundtrip d
        roundtrip e
        roundtrip f

    test "case objects":
      var
        c1 = CaseObjectRef(kind: B, b: 100)
        c2 = CaseObjectRef(kind: A, a: 80, other: CaseObjectRef(kind: B))
        c3 = HoldsCaseObject(value: CaseObject(kind: A, a: 60, other: c1))

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
        t4 = {0: "test", 1: "other"}.toTable()

      t3["test"] = 0
      t3["other"] = 1

      roundtrip t1
      roundtrip t2
      roundtrip t3
      roundtrip t4

    test "sets":
      var s1 = toHashSet([1, 2, 3, 1, 4, 2])
      var s2 = HoldsSet(a: 100, s: toHashSet(["a", "b", "c"]))

      roundtrip s1
      roundtrip s2

    test "tuple":
      var t = (0, "e")
      var namedT = (a: 0, b: "e")
      roundtrip t
      roundtrip namedT

proc executeReaderWriterTests*(Format: type) =
  mixin init, Reader, Writer

  type
    ReaderType = Reader Format

  suite(typetraits.name(Format) & " read/write tests"):
    test "Low-level field reader test":
      let barFields = fieldReadersTable(Bar, ReaderType)
      var idx = 0

      var fieldReader = findFieldReader(barFields[], "b", idx)
      check fieldReader != nil and idx == 1

      # check that the reader can be found again starting from a higher index
      fieldReader = findFieldReader(barFields[], "b", idx)
      check fieldReader != nil and idx == 1

      var bytes = Format.encode("test")
      var stream = unsafeMemoryInput(bytes)
      var reader = ReaderType.init(stream)

      var bar: Bar
      fieldReader(bar, reader)

      check bar.b == "test"

    test "Ignored fields should not be included in the field readers table":
      var pos = 0
      let bazFields = fieldReadersTable(Baz, ReaderType)
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

