import
  typetraits, unittest,
  stew/shims/macros, stew/objects,
  ../serialization/object_serialization,
  ../serialization/testing/generic_suite

type
  Untrusted = object
  Trusted = object

  Signature = object
    p: int
    k: float

  TrustedSignature = object
    data: string

  SignatureHolder[TrustLevel] = object
    when TrustLevel is Trusted:
      sig: TrustedSignature
      origin: string
    else:
      sig: Signature

func collectFields(T: type): seq[string] =
  enumAllSerializedFields(T):
    result.add(name(FieldType) & " " & fieldName & fieldCaseDiscriminator)

suite "object serialization":
  test "custom fields order":
    check collectFields(Simple) == @["Meter distance", "int x", "string y"]

  test "tuples handling":
    var fieldsList = newSeq[string]()

    enumAllSerializedFields(HoldsTuples):
      fieldsList.add(fieldName & ": " & $isTuple(FieldType))

    check fieldsList == @["t1: true", "t2: true", "t3: true"]

  test "when statements":
    check collectFields(SignatureHolder[Trusted]) == @["TrustedSignature sig", "string origin"]
    check collectFields(SignatureHolder[Untrusted]) == @["Signature sig"]

