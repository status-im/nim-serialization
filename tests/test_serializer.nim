import
  unittest2,
  ./utils/serializer

# XXX: export parseInt or bind it
#      required for write tuple
import std/strutils

proc rountrip[T](val: T): bool =
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
