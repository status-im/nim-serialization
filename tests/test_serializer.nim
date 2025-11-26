{.push raises: [], gcsafe.}

import
  unittest2,
  ./utils/serializer

proc rountrip[T](val: T): bool {.raises: [SerializationError].} =
  let ser = Ser.encode(val)
  val == Ser.decode(ser, T)

suite "Rountrips":
  test "int":
    check:
      rountrip(1)
      rountrip(-1)
      rountrip(1'u8)
      rountrip(123)

  test "float":
    check:
      rountrip(1)
      rountrip(1.23)
      rountrip(1.23'f32)
      rountrip(1.23'f64)
  
  test "string":
    check:
      rountrip("abc")
      rountrip("")

  test "seq":
    check:
      rountrip(@[1])
      rountrip(@[1, 2, 3])
      rountrip(newSeq[int]())
      rountrip(@["foo", "bar"])

  test "object":
    type Foo = object
      bar: string
      baz: int
    check:
      rountrip(Foo())
      rountrip(Foo(bar: "abc", baz: 123))

  test "nested object":
    type Bar = object
      x: string
    type Foo = object
      bar: Bar
    check:
      rountrip(Foo())
      rountrip(Foo(bar: Bar(x: "abc")))

  test "tuple":
    check:
      rountrip((1, 2))
      rountrip(("abc", 123))
      rountrip(("foo", ("bar", 123)))

  test "bool":
    check:
      rountrip(true)
      rountrip(false)

  test "enum":
    type Foo = enum
      fooA
      fooB
    check:
      rountrip(fooA)
      rountrip(fooB)

  test "ref":
    let val = new(string)
    val[] = "abc"
    let ser = Ser.encode(val)
    check val[] == Ser.decode(ser, typeof(val))[]

  test "ref nil":
    var val: ref string
    let ser = Ser.encode(val)
    check Ser.decode(ser, typeof(val)).isNil()

type StringLimErr = object of SerializationError
type StringLim = distinct string

proc `==`(a, b: StringLim): bool {.borrow.}
proc add(a: var StringLim, b: char) {.borrow.}

proc readValue(r: var SerReader, val: var StringLim) {.raises: [IOError, SerializationError].} =
  consumeKind r, SerKind.String
  let L = r.readUint64()
  if L > r.conf.limit.uint64:
    raise newException(StringLimErr, "limit err")
  for _ in 0 ..< L:
    val.add r.stream.read().char

suite "Config":
  test "pass let conf":
    let val = "1234567890"
    let ser = Ser.encode(val)

    let conf10 = SerConf(limit: 10)
    check Ser.decode(ser, StringLim, conf = conf10) == val.StringLim
    check Ser.decode(ser, StringLim, conf10) == val.StringLim

    let conf5 = SerConf(limit: 5)
    expect StringLimErr:
      discard Ser.decode(ser, StringLim, conf = conf5)
    expect StringLimErr:
      discard Ser.decode(ser, StringLim, conf5)

  test "pass const conf":
    let val = "1234567890"
    let ser = Ser.encode(val)

    const conf10 = SerConf(limit: 10)
    check Ser.decode(ser, StringLim, conf = conf10) == val.StringLim
    check Ser.decode(ser, StringLim, conf10) == val.StringLim

    const conf5 = SerConf(limit: 5)
    expect StringLimErr:
      discard Ser.decode(ser, StringLim, conf = conf5)
    expect StringLimErr:
      discard Ser.decode(ser, StringLim, conf5)

  test "pass inlined conf":
    let val = "1234567890"
    let ser = Ser.encode(val)

    check Ser.decode(ser, StringLim, conf = SerConf(limit: 10)) == val.StringLim
    check Ser.decode(ser, StringLim, SerConf(limit: 10)) == val.StringLim

    expect StringLimErr:
      discard Ser.decode(ser, StringLim, conf = SerConf(limit: 5))
    expect StringLimErr:
      discard Ser.decode(ser, StringLim, SerConf(limit: 5))

  test "pass expression conf":
    let val = "1234567890"
    let ser = Ser.encode(val)

    template conf10: untyped =
      var conf = SerConf(limit: 10)
      conf

    check Ser.decode(ser, StringLim, conf = conf10) == val.StringLim
    check Ser.decode(ser, StringLim, conf10) == val.StringLim

    template conf5: untyped =
      var conf = SerConf(limit: 5)
      conf

    expect StringLimErr:
      discard Ser.decode(ser, StringLim, conf = conf5)
    expect StringLimErr:
      discard Ser.decode(ser, StringLim, conf5)

  test "multi params":
    func init(
        R: type SerReader,
        stream: InputStream,
        limit1: int,
        limit2: int,
        conf = default(SerConf)
    ): R =
      R(stream: stream, conf: SerConf(limit: conf.limit + limit1 + limit2))

    let val = "1234567890"
    let ser = Ser.encode(val)

    let lim1 = 10
    let lim2 = 0
    check:
      Ser.decode(ser, StringLim, 10, 0) == val.StringLim
      Ser.decode(ser, StringLim, 0, 10) == val.StringLim
      Ser.decode(ser, StringLim, 0, 0, SerConf(limit: 10)) == val.StringLim
      Ser.decode(ser, StringLim, limit1 = 10, limit2 = 0) == val.StringLim
      Ser.decode(ser, StringLim, limit1 = 0, limit2 = 10) == val.StringLim
      Ser.decode(ser, StringLim, lim1, lim2) == val.StringLim
