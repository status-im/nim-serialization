{.push raises: [], gcsafe.}

import
  ./utils/[serializer, serializer_std],
  ../serialization,
  ../serialization/testing/generic_suite

proc readValue(r: var SerReader, value: var CaseObject) {.raises: [IOError, SerializationError].} =
  var
    kindSpecified = false
    valueSpecified = false
    otherSpecified = false
  for fieldName in readObjectFields(r):
    case fieldName
    of "kind":
      value = CaseObject(kind: r.readValue(ObjectKind))
      kindSpecified = true
      case value.kind
      of A:
        discard
      of B:
        otherSpecified = true
    of "a":
      if kindSpecified:
        case value.kind
        of A:
          r.readValue(value.a)
        of B:
          doAssert false
      else:
        doAssert false
      valueSpecified = true
    of "other":
      if kindSpecified:
        case value.kind
        of A:
          r.readValue(value.other)
        of B:
          doAssert false
      else:
        doAssert false
      otherSpecified = true
    of "b":
      if kindSpecified:
        case value.kind
        of B:
          r.readValue(value.b)
        of A:
          doAssert false
      else:
        doAssert false
      valueSpecified = true
    else:
      doAssert false
  if not (kindSpecified and valueSpecified and otherSpecified):
    doAssert false

executeReaderWriterTests Ser
