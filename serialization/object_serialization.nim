import macros

template dontSerialize* {.pragma.}
  ## Specifies that a certain field should be ignored for
  ## the purposes of serialization

template customSerialization* {.pragma.}
  ## This pragma can be applied to a record field to enable the
  ## use of custom `readValue` overloads that also take a reference
  ## to the object holding the field.
  ##
  ## TODO: deprecate this in favor of readField(T, field, InputArchive)

template eachSerializedFieldImpl*[T](x: T, op: untyped) =
  for k, v in fieldPairs(x):
    when not hasCustomPragma(v, dontSerialize):
      op(k, v)

proc totalSerializedFieldsImpl(T: type): int =
  mixin eachSerializedFieldImpl

  proc helper: int =
    var dummy: T
    template countFields(x) = inc result
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

