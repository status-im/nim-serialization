{.used.}

import
  unittest2,
  ../serialization

serializationFormat ParentFormat, version = 1

type
  SomeReader[Flavor = ParentFormat] = object
  SomeWriter[Flavor = ParentFormat] = object

ParentFormat.setReader SomeReader
ParentFormat.setWriter SomeWriter, PreferredOutput = string

createFlavor ParentFormat, ChildFlavor

template sound(_: type ParentFormat): string = "meow"
func speed(_: type ParentFormat): int = 1001

suite "Flavor":
  test "flavor inherited from serializationFormat":
    check ChildFlavor is ParentFormat

  test "flavor can use parent template":
    check ChildFlavor.sound() == "meow"

  test "flavor can use parent function":
    check ChildFlavor.speed() == 1001

  test "flavor reader/writer type":
    check Reader(ChildFlavor) is SomeReader[ChildFlavor]
    check Writer(ChildFlavor) is SomeWriter[ChildFlavor]

  test "default flavor reader/writer type is parent type":
    check Reader(ParentFormat) is SomeReader[ParentFormat]
    check Writer(ParentFormat) is SomeWriter[ParentFormat]
