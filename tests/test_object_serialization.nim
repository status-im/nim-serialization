import
  typetraits, unittest2,
  stew/shims/macros, stew/objects,
  ../serialization/object_serialization,
  ../serialization/testing/generic_suite

{.used.}

suite "object serialization":
  setup:
    var fieldsList = newSeq[string]()

  test "custom fields order":
    enumAllSerializedFields(Simple):
      fieldsList.add(name(FieldType) & " " & fieldName & fieldCaseDiscriminator)

    check fieldsList == @["Meter distance", "int x", "string y"]

  test "tuples handling":
    enumAllSerializedFields(HoldsTuples):
      fieldsList.add(fieldName & ": " & $isTuple(FieldType))

    check fieldsList == @["t1: true", "t2: true", "t3: true"]

