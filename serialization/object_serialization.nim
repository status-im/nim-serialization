import
  stew/shims/macros, stew/objects

type
  FieldTag[RecordType; fieldName: static string; FieldType] = distinct void

let
  # Identifiers affecting the public interface of the library:
  valueVar {.compileTime.} = ident "value"
  readerVar {.compileTime.} = ident "reader"
  writerVar {.compileTime.} = ident "writer"
  holderVar {.compileTime.} = ident "holder"
  fieldNameVar {.compileTime.} = ident "fieldName"
  FieldTypeSym {.compileTime.} = ident "FieldType"

template dontSerialize* {.pragma.}
  ## Specifies that a certain field should be ignored for
  ## the purposes of serialization

template enumInstanceSerializedFields*(obj: auto,
                                       fieldNameVar, fieldVar,
                                       body: untyped) =
  ## Expands a block over all serialized fields of an object.
  ##
  ## Inside the block body, the passed `fieldNameVar` identifier
  ## will refer to the name of each field as a string. `fieldVar`
  ## will refer to the field value.
  ##
  ## The order of visited fields matches the order of the fields in
  ## the object definition unless `serialziedFields` is used to specify
  ## a different order. Fields marked with the `dontSerialize` pragma
  ## are skipped.
  ##
  ## If the visited object is a case object, only the currently active
  ## fields will be visited. During de-serialization, case discriminators
  ## will be read first and the iteration will continue depending on the
  ## value being deserialized.
  ##
  type ObjType = type(obj)

  for fieldNameVar, fieldVar in fieldPairs(obj):
    when not hasCustomPragmaFixed(ObjType, fieldNameVar, dontSerialize):
      body

macro enumAllSerializedFieldsImpl(T: type, body: untyped): untyped =
  ## Expands a block over all fields of a type
  ##
  ## Please note that the main difference between
  ## `enumInstanceSerializedFields` and `enumAllSerializedFields`
  ## is that the later will visit all fields of case objects.
  ##
  ## Inside the block body, the following symbols will be defined:
  ##
  ##  * `fieldName`
  ##    String literal for the field name
  ##
  ##  * `FieldType`
  ##    Type alias for the field type
  ##
  ##  * `fieldCaseDisciminator`
  ##    String literal denoting the name of the case object
  ##    discrimator under which the visited field is nested.
  ##    If the field is not nested in a specific case branch,
  ##    this will be an empty string.
  ##
  ##  * `fieldCaseBranches`
  ##    A set literal node denoting the possible values of the
  ##    case object discrimator which make this field accessible.
  ##
  ## The order of visited fields matches the order of the fields in
  ## the object definition unless `serialziedFields` is used to specify
  ## a different order. Fields marked with the `dontSerialize` pragma
  ## are skipped.
  ##
  var typeAst = getType(T)[1]
  var typeImpl = getImpl(typeAst)
  result = newStmtList()

  for field in recordFields(typeImpl):
    if field.readPragma("dontSerialize") != nil:
      continue

    let
      fieldType = field.typ
      fieldIdent = field.name
      fieldName = newLit($fieldIdent)
      discrimator = newLit(if field.caseField == nil: ""
                           else: $field.caseField[0])
      branches = field.caseBranch

    result.add quote do:
      block:
        template `fieldNameVar`: auto = `fieldName`
        template fieldCaseDisciminator: auto = `discrimator`
        template fieldCaseBranches: auto = `branches`
        # type `fieldTypeVar` = `fieldType`
        # TODO: This is a work-around for a classic Nim issue:
        type `FieldTypeSym` = type(default(`T`).`fieldIdent`)
        `body`

template enumAllSerializedFields*(T: type, body): untyped =
  when T is ref|ptr:
    type TT = type(default(T)[])
    enumAllSerializedFieldsImpl(TT, body)
  else:
    enumAllSerializedFieldsImpl(T, body)

func isCaseObject*(T: type): bool {.compileTime.} =
  genExpr:
    enumAllSerializedFields(T):
      if fieldCaseDisciminator != "":
        return newLit(true)

    newLit(false)

type
  FieldMarkerImpl*[name: static string] = object

  FieldReader*[RecordType, Reader] = tuple[
    fieldName: string,
    reader: proc (rec: var RecordType, reader: var Reader) {.gcsafe, nimcall.}
  ]

  FieldReadersTable*[RecordType, Reader] = openarray[FieldReader[RecordType, Reader]]

proc totalSerializedFieldsImpl(T: type): int =
  mixin enumAllSerializedFields
  enumAllSerializedFields(T): inc result

template totalSerializedFields*(T: type): int =
  (static(totalSerializedFieldsImpl(T)))

macro customSerialization*(field: untyped, definition): untyped =
  discard

template readFieldIMPL[Reader](field: type FieldTag,
                               reader: var Reader): untyped =
  mixin readValue
  reader.readValue(field.FieldType)

proc makeFieldReadersTable(RecordType, Reader: distinct type):
                           seq[FieldReader[RecordType, Reader]] =
  mixin enumAllSerializedFields, readFieldIMPL

  enumAllSerializedFields(RecordType):
    proc readField(obj: var RecordType, reader: var Reader) {.gcsafe, nimcall.} =
      try:
        type F = FieldTag[RecordType, fieldName, type(FieldType)]
        obj.field(fieldName) = readFieldIMPL(F, reader)
      except SerializationError:
        raise
      except CatchableError as err:
        reader.handleReadException(`RecordType`, fieldName,
                                   obj.field(fieldName), err)

    result.add((fieldName, readField))

proc fieldReadersTable*(RecordType, Reader: distinct type):
                        ptr seq[FieldReader[RecordType, Reader]] =
  mixin readValue
  var tbl {.global.} = makeFieldReadersTable(RecordType, Reader)
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

macro setSerializedFields*(T: typedesc, fields: varargs[untyped]): untyped =
  var fieldsArray = newTree(nnkBracket)
  for f in fields: fieldsArray.add newCall(bindSym"ident", newLit($f))

  template payload(T: untyped, fieldsArray) {.dirty.} =
    bind default, quote, add, getType, newStmtList,
         ident, newLit, newDotExpr, `$`, `[]`, getAst

    macro enumInstanceSerializedFields*(ins: T,
                                        fieldNameVar, fieldVar,
                                        body: untyped): untyped =
      var
        fields = fieldsArray
        res = newStmtList()

      for field in fields:
        let
          fieldName = newLit($field)
          fieldAccessor = newDotExpr(ins, field)

        # TODO replace with getAst once it's ready
        template fieldPayload(fieldNameVar, fieldName, fieldVar,
                              fieldAccessor, body) =
          block:
            const fieldNameVar = fieldName
            template fieldVar: auto = fieldAccessor
            body

        res.add getAst(fieldPayload(fieldNameVar, fieldName, fieldVar,
                                    fieldAccessor, body))

      return res

    macro enumAllSerializedFields*(typ: type T, body: untyped): untyped =
      var
        fields = fieldsArray
        res = newStmtList()
        typ = getType(typ)

      for field in fields:
        let
          fieldName = newLit($field)
          fieldNameVar = ident "fieldName"
          FieldTypeSym = ident "FieldType"

        # TODO replace with getAst once it's ready
        template fieldPayload(fieldNameVar, fieldName,
                              fieldTypeVar, typ, field,
                              body) =
          block:
            const fieldNameVar = fieldName
            type fieldTypeVar = type(default(typ).field)

            template fieldCaseDisciminator: auto = ""
            template fieldCaseBranches: auto = nil

            body

        res.add getAst(fieldPayload(fieldNameVar, fieldName,
                                    FieldTypeSym, typ, field,
                                    body))

      return res

  return getAst(payload(T, fieldsArray))

proc getReaderAndWriter(customSerializationBody: NimNode): (NimNode, NimNode) =
  template fail(n) =
    error "useCustomSerialization expects a block with only `read` and `write` definitions", n

  for n in customSerializationBody:
    if n.kind in nnkCallKinds:
      if eqIdent(n[0], "read"):
        result[0] = n[1]
      elif eqIdent(n[0], "write"):
        result[1] = n[1]
      else:
        fail n[0]
    elif n.kind == nnkCommentStmt:
      continue
    else:
      fail n

proc genCustomSerializationForField(Format, field,
                                    readBody, writeBody: NimNode): NimNode =
  var
    RecordType = field[0]
    fieldIdent = field[1]
    fieldName = newLit $fieldIdent
    FieldType = genSym(nskType, "FieldType")

  result = newStmtList()
  result.add quote do:
    type `FieldType` = type default(`RecordType`).`fieldIdent`

  if readBody != nil:
    result.add quote do:
      type Reader = ReaderType(`Format`)
      proc readFieldIMPL*(F: type FieldTag[`RecordType`, `fieldName`, auto],
                          `readerVar`: var Reader): `FieldType` =
        `readBody`

  if writeBody != nil:
    result.add quote do:
      type Writer = WriterType(`Format`)
      proc writeFieldIMPL*(F: type FieldTag[`RecordType`, `fieldName`, auto],
                           `writerVar`: var Writer) =
        `writeBody`

proc genCustomSerializationForType(Format, typ: NimNode,
                                   readBody, writeBody: NimNode): NimNode =
  result = newStmtList()

  if readBody != nil:
    result.add quote do:
      type Reader = ReaderType(`Format`)
      proc readValue*(`readerVar`: var Reader, T: type `typ`): `typ` =
        `readBody`

  if writeBody != nil:
    result.add quote do:
      type Writer = WriterType(`Format`)
      proc writeValue*(`writerVar`: var Writer, `valueVar`: `typ`) =
        `writeBody`

macro useCustomSerialization*(Format: typed, field: untyped, body: untyped): untyped =
  let (readBody, writeBody) = getReaderAndWriter(body)
  if field.kind == nnkDotExpr:
    result = genCustomSerializationForField(Format, field, readBody, writeBody)
  elif field.kind in {nnkIdent, nnkAccQuoted}:
    result = genCustomSerializationForType(Format, field, readBody, writeBody)
  else:
    error "useCustomSerialization expects a type name or a field of a type (e.g. MyType.myField)"

  when defined(debugUseCustomSerialization):
    echo result.repr

