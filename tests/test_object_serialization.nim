import
  typetraits, unittest2,
  stew/shims/macros, stew/objects,
  ../serialization/object_serialization,
  ../serialization/testing/generic_suite

{.used.}

suite "object serialization":
  test "custom fields order":
    var fieldsList = newSeq[string]()
    enumAllSerializedFields(Simple):
      fieldsList.add(name(FieldType) & " " & fieldName & fieldCaseDiscriminator)

    check fieldsList == @["Meter distance", "int x", "string y"]

  test "tuples handling":
    var fieldsList = newSeq[string]()
    enumAllSerializedFields(HoldsTuples):
      fieldsList.add(fieldName & ": " & $isTuple(FieldType))

    check fieldsList == @["t1: true", "t2: true", "t3: true"]

