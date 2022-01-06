import
  stew/shims/macros, stew/objects,
  ./errors

type
  DefaultFlavor* = object
  FieldTag*[RecordType; fieldName: static string; FieldType] = distinct void

let
  # Identifiers affecting the public interface of the library:
  valueSym {.compileTime.} = ident "value"
  readerSym {.compileTime.} = ident "reader"
  writerSym {.compileTime.} = ident "writer"
  holderSym {.compileTime.} = ident "holder"

template dontSerialize* {.pragma.}
  ## Specifies that a certain field should be ignored for
  ## the purposes of serialization

template serializedFieldName*(name: string) {.pragma.}
  ## Specifies an alternative name for the field that will
  ## be used in formats that include field names.

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
  type ObjType {.used.} = type(obj)

  for fieldName, fieldVar in fieldPairs(obj):
    when not hasCustomPragmaFixed(ObjType, fieldName, dontSerialize):
      when hasCustomPragmaFixed(ObjType, fieldName, serializedFieldName):
        const fieldNameVar = getCustomPragmaFixed(ObjType, fieldName, serializedFieldName)
      else:
        const fieldNameVar = fieldName
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
  ##    String literal for the field name.
  ##    The value can be affected by the `serializedFieldName` pragma.
  ##
  ##  * `realFieldName`
  ##    String literal for actual field name in the Nim type
  ##    definition. Not affected by the `serializedFieldName` pragma.
  ##
  ##  * `FieldType`
  ##    Type alias for the field type
  ##
  ##  * `fieldCaseDiscriminator`
  ##    String literal denoting the name of the case object
  ##    discriminator under which the visited field is nested.
  ##    If the field is not nested in a specific case branch,
  ##    this will be an empty string.
  ##
  ##  * `fieldCaseBranches`
  ##    A set literal node denoting the possible values of the
  ##    case object discriminator which make this field accessible.
  ##
  ## The order of visited fields matches the order of the fields in
  ## the object definition unless `serialziedFields` is used to specify
  ## a different order. Fields marked with the `dontSerialize` pragma
  ## are skipped.
  ##
  var typeAst = getType(T)[1]
  var typeImpl: NimNode
  let isSymbol = not typeAst.isTuple

  if not isSymbol:
    typeImpl = typeAst
  else:
    typeImpl = getImpl(typeAst)
  result = newStmtList()

  var i = 0
  for field in recordFields(typeImpl):
    if field.readPragma("dontSerialize") != nil:
      continue

    let
      fieldType = field.typ
      fieldIdent = field.name
      realFieldName = newLit($fieldIdent.skipPragma)
      serializedFieldName = field.readPragma("serializedFieldName")
      fieldName = if serializedFieldName == nil: realFieldName
                  else: serializedFieldName
      discriminator = newLit(if field.caseField == nil: ""
                           else: $field.caseField[0].skipPragma)
      branches = field.caseBranch
      fieldIndex = newLit(i)

    let fieldNameDefs =
      if isSymbol:
        quote:
          const fieldName {.inject, used.} = `fieldName`
          const realFieldName {.inject, used.} = `realFieldName`
      else:
        quote:
          const fieldName {.inject, used.} = $`fieldIndex`
          const realFieldName {.inject, used.} = $`fieldIndex`
          # we can't access .Fieldn, so our helper knows
          # to parseInt this

    let field =
      if isSymbol:
        quote do: declval(`T`).`fieldIdent`
      else:
        quote do: declval(`T`)[`fieldIndex`]

    result.add quote do:
      block:
        `fieldNameDefs`

        type FieldType {.inject, used.} = type(`field`)

        template fieldCaseDiscriminator: auto {.used.} = `discriminator`
        template fieldCaseBranches: auto {.used.} = `branches`

        `body`

    i += 1

template enumAllSerializedFields*(T: type, body): untyped =
  when T is ref|ptr:
    type TT = type(default(T)[])
    enumAllSerializedFieldsImpl(TT, body)
  else:
    enumAllSerializedFieldsImpl(T, body)

func isCaseObject*(T: type): bool {.compileTime.} =
  genSimpleExpr:
    enumAllSerializedFields(T):
      if fieldCaseDiscriminator != "":
        return newLit(true)

    newLit(false)

type
  FieldMarkerImpl*[name: static string] = object

  FieldReader*[RecordType, Reader] = tuple[
    fieldName: string,
    reader: proc (rec: var RecordType, reader: var Reader)
                 {.gcsafe, nimcall, raises: [SerializationError, Defect].}
  ]

  FieldReadersTable*[RecordType, Reader] = openArray[FieldReader[RecordType, Reader]]

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
  {.gcsafe.}: # needed by Nim-1.6
    reader.readValue(field.FieldType)

template writeFieldIMPL*[Writer](writer: var Writer,
                                 fieldTag: type FieldTag,
                                 fieldVal: auto,
                                 holderObj: auto) =
  mixin writeValue
  writer.writeValue(fieldVal)

proc makeFieldReadersTable(RecordType, ReaderType: distinct type):
                           seq[FieldReader[RecordType, ReaderType]] =
  mixin enumAllSerializedFields, readFieldIMPL, handleReadException

  enumAllSerializedFields(RecordType):
    proc readField(obj: var RecordType, reader: var ReaderType)
                  {.gcsafe, nimcall, raises: [SerializationError, Defect].} =
      when RecordType is tuple:
        const i = fieldName.parseInt
      try:
        type F = FieldTag[RecordType, realFieldName, type(FieldType)]
        when RecordType is tuple:
          obj[i] = readFieldIMPL(F, reader)
        else:
          # TODO: The `FieldType` coercion below is required to deal
          # with a nim bug caused by the distinct `ssz.List` type.
          # It seems to break the generics cache mechanism, which
          # leads to an incorrect return type being reported from
          # the `readFieldIMPL` function.
          field(obj, realFieldName) = FieldType readFieldIMPL(F, reader)
      except SerializationError as err:
        raise err
      except CatchableError as err:
        reader.handleReadException(
          `RecordType`,
          fieldName,
          when RecordType is tuple: obj[i] else: field(obj, realFieldName),
          err)

    result.add((fieldName, readField))

proc fieldReadersTable*(RecordType, ReaderType: distinct type):
                        ptr seq[FieldReader[RecordType, ReaderType]] =
  mixin readValue

  # careful: https://github.com/nim-lang/Nim/issues/17085
  # TODO why is this even here? one could just return the function pointer
  #      to the field reader directly instead of going through this seq etc
  var tbl {.threadvar.}: ref seq[FieldReader[RecordType, ReaderType]]
  if tbl == nil:
    tbl = new typeof(tbl)
    tbl[] = makeFieldReadersTable(RecordType, ReaderType)
  return addr(tbl[])

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
            const fieldNameVar {.inject, used.} = fieldName
            template fieldVar: auto {.used.} = fieldAccessor

            body

        res.add getAst(fieldPayload(fieldNameVar, fieldName,
                                    fieldVar, fieldAccessor,
                                    body))
      return res

    macro enumAllSerializedFields*(typ: type T, body: untyped): untyped =
      var
        fields = fieldsArray
        res = newStmtList()
        typ = getType(typ)

      for field in fields:
        let fieldName = newLit($field)

        # TODO replace with getAst once it's ready
        template fieldPayload(fieldNameValue, typ, field, body) =
          block:
            const fieldName {.inject, used.} = fieldNameValue
            const realFieldName {.inject, used.} = fieldNameValue

            type FieldType {.inject, used.} = type(declval(typ).field)

            template fieldCaseDiscriminator: auto {.used.} = ""
            template fieldCaseBranches: auto {.used.} = nil

            body

        res.add getAst(fieldPayload(fieldName, typ, field, body))

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
    type `FieldType` = type declval(`RecordType`).`fieldIdent`

  if readBody != nil:
    result.add quote do:
      type ReaderType = Reader(`Format`)
      proc readFieldIMPL*(F: type FieldTag[`RecordType`, `fieldName`, auto],
                          `readerSym`: var ReaderType): `FieldType`
                         {.raises: [IOError, SerializationError, Defect].} =
        `readBody`

  if writeBody != nil:
    result.add quote do:
      type WriterType = Writer(`Format`)
      proc writeFieldIMPL*(`writerSym`: var WriterType,
                           F: type FieldTag[`RecordType`, `fieldName`, auto],
                           `valueSym`: auto,
                           `holderSym`: `RecordType`)
                          {.raises: [IOError, SerializationError, Defect].} =
        `writeBody`

proc genCustomSerializationForType(Format, typ: NimNode,
                                   readBody, writeBody: NimNode): NimNode =
  result = newStmtList()

  if readBody != nil:
    result.add quote do:
      type ReaderType = Reader(`Format`)
      proc readValue*(`readerSym`: var ReaderType, T: type `typ`): `typ`
                     {.raises: [IOError, SerializationError, Defect].} =
        `readBody`

  if writeBody != nil:
    result.add quote do:
      type WriterType = Writer(`Format`)
      proc writeValue*(`writerSym`: var WriterType, `valueSym`: `typ`)
                      {.raises: [IOError, SerializationError, Defect].} =
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

