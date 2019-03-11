import
  std_shims/macros_shim

template dontSerialize* {.pragma.}
  ## Specifies that a certain field should be ignored for
  ## the purposes of serialization

type
  FieldMarkerImpl*[name: static string] = object

  FieldReader*[RecordType, Reader] = tuple[
    fieldName: string,
    reader: proc (rec: var RecordType, reader: var Reader) {.nimcall.}
  ]

  FieldReadersTable*[RecordType, Reader] = openarray[FieldReader[RecordType, Reader]]

template eachSerializedFieldImpl*[T](x: T, op: untyped) =
  when false:
    static: echo treeRepr(T.getTypeImpl)

  for k, v in fieldPairs(x):
    when true: # not hasCustomPragma(v, dontSerialize):
      op(k, v)

proc totalSerializedFieldsImpl(T: type): int =
  mixin eachSerializedFieldImpl

  proc helper: int =
    var dummy: T
    template countFields(k, v) = inc result
    eachSerializedFieldImpl(dummy, countFields)

  const res = helper()
  return res

template totalSerializedFields*(T: type): int =
  (static(totalSerializedFieldsImpl(T)))

macro serialziedFields*(T: typedesc, fields: varargs[untyped]): untyped =
  var body = newStmtList()
  let
    ins = genSym(nskParam, "instance")
    op = genSym(nskParam, "op")

  for field in fields:
    body.add quote do: `op`(`ins`.`field`)

  result = quote do:
    template eachSerializedFieldImpl*(`ins`: `T`, `op`: untyped) {.inject.} =
      `body`

template serializeFields*(value: auto, fieldName, fieldValue, body: untyped) =
  # TODO: this would be nicer as a for loop macro
  mixin eachSerializedFieldImpl

  template op(fieldName, fieldValue: untyped) = body
  eachSerializedFieldImpl(value, op)

template deserializeFields*(value: auto, fieldName, fieldValue, body: untyped) =
  # TODO: this would be nicer as a for loop macro
  mixin eachSerializedFieldImpl

  template op(fieldName, fieldValue: untyped) = body
  eachSerializedFieldImpl(value, op)

macro customSerialization*(field: untyped, definition): untyped =
  discard

proc hasDontSerialize(pragmas: NimNode): bool =
  if pragmas == nil: return false
  let dontSerialize = bindSym "dontSerialize"
  for p in pragmas:
    if p == dontSerialize:
      return true

macro makeFieldReadersTable(RecordType, Reader: distinct type): untyped =
  var obj = RecordType.getType[1].getImpl

  result = newTree(nnkBracket)

  for field in recordFields(obj):
    let fieldName = field.name
    if not hasDontSerialize(field.pragmas):
      var handler = quote do:
        return proc (obj: var `RecordType`, reader: var `Reader`) {.nimcall.} =
          reader.readValue(obj.`fieldName`)

      result.add newTree(nnkTupleConstr, newLit($fieldName), handler[0])

proc fieldReadersTable*(RecordType, Reader: distinct type):
                        ptr seq[FieldReader[RecordType, Reader]] {.gcsafe.} =
  mixin readValue
  var tbl {.global.} = @(makeFieldReadersTable(RecordType, Reader))
  {.gcsafe.}:
    return addr(tbl)

proc findFieldReader*(fieldsTable: FieldReadersTable,
                      fieldName: string,
                      expectedFieldPos: var int): auto =
  for i in expectedFieldPos ..< fieldsTable.len:
    if fieldsTable[i].fieldName == fieldName:
      expectedFieldPos = i + 1
      return fieldsTable[i].reader

  for i in 0 ..< expectedFieldPos:
    if fieldsTable[i].fieldName == fieldName:
      return fieldsTable[i].reader

  return nil

