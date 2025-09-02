# nim-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at https://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at https://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

{.push raises: [].}

# Nim limits case object discriminators to types with a `low` value of 0.
#
# In the context of serialization, Nim case objects typically translate to
# tagged unions, where the discriminator tag may not be zero based.
#
# We still want the type definition to indicate the serialization tag values;
# however, Nim does not support attaching pragma to enum field values.
# As fields can further be shared between multiple different case branches,
# pragma based annotations are quite limited.
#
# To keep the type definitions simple, this file introduces a helper macro that
# extends case object discriminator support for holey enums without 0 values.
#
# To use the macro:
#
# 1. Annotate the case object type with `{.allowDiscriminatorsWithoutZero.}`
# 2. Change init logic from `T(a: 1, b: 2)` syntax to `T.init(a = 1, b = 2)`
# 3. Change `fields` and `fieldPairs` usage to `withFields` / `withFieldPairs`
#
# When inspecting the type from another macro, one may encounter discriminators
# that have been assigned new field names internally. If that happens, the
# original field name is exposed via pragma `{.origin: "originalFieldName".}`

import std/macros
export macros

when (NimMajor, NimMinor) < (2, 0):
  # https://nim-lang.org/docs/manual_experimental.html#extended-macro-pragmas
  # For now, macros can return an unused type definition where the right-hand
  # node is of kind `nnkStmtListType`. Declarations in this node will be
  # attached to the same scope as the parent scope of the type section.
  {.error: "`allowDiscriminatorsWithoutZero` requires " &
    "extended macro pragmas (Nim 2.0+)".}

func isSupportedAsDiscriminator(T: typedesc): bool =
  when compiles(T.low.int):
    T.low.int == 0
  else:
    false

macro withZeroField(typ: typedesc[enum]): untyped =
  let impl = typ.getImpl()
  doAssert impl.kind == nnkTypeDef
  doAssert impl[2].kind == nnkEnumTy

  var def = nnkEnumTy.newTree(
    newEmptyNode(),
    nskEnumField.genSym "")
  for i, field in impl[2]:
    case field.kind
    of nnkEmpty:
      doAssert i == 0
    of nnkEnumFieldDef:
      def.add nnkEnumFieldDef.newTree(nskEnumField.genSym $field[0], field[1])
    of nnkSym:
      def.add nskEnumField.genSym $field
    else:
      error "unexpected enum field", field
  def

template withNodes*(
    root: NimNode, kindParam: NimNodeKind, body: untyped): untyped =
  block:
    func dfs(node: NimNode) =
      for i in 0 ..< node.len:
        dfs node[i]
        if node[i].kind == kindParam:
          let
            parent {.inject, used.} = node
            childIndex {.inject, used.} = i
          body
    dfs root

func splitId(node: NimNode): tuple[id: NimNode, isExported: bool] =
  case node.kind
  of nnkPostfix:
    doAssert $node[0] == "*"
    (node[1], true)
  of nnkIdent:
    (node, false)
  else:
    error "unexpected identifier", node

func makeId(id: NimNode, isExported: bool): NimNode =
  if isExported:
    nnkPostfix.newTree(ident "*", id)
  else:
    id

template originalFieldName*(_: string) {.pragma.}

func getOriginalFieldName*(ident: NimNode): string =
  let name =
    case ident.kind
    of nnkPostfix:
      ident[1]
    else:
      ident
  case name.kind
  of nnkPragmaExpr:
    let originalNameSym = bindSym "originalFieldName"
    for pragma in name[1]:
      if pragma.kind == nnkExprColonExpr and pragma[0] == originalNameSym:
        doAssert pragma[1].kind == nnkStrLit
        return $pragma[1]
    $name[0]
  else:
    $name

macro allowDiscriminatorsWithoutZero*(typ: untyped{nkTypeDef}): untyped =
  let def = typ[2]
  if def.kind != nnkObjectTy:
    return typ

  doAssert typ[0].kind == nnkPragmaExpr
  let
    (T, typIsExported) = typ[0][0].splitId()
    initId = makeId(ident "init", typIsExported)
    fieldsId = makeId(ident "fields", typIsExported)
    fieldPairsId = makeId(ident "fieldPairs", typIsExported)
    doWithFields = ident "doWithFields"
    doWithFieldPairs = ident "doWithFieldPairs"
    dollarId = makeId(ident "$", typIsExported)
    arg = nskForVar.genSym "arg"
    code = nskVar.genSym "code"
    keyParam = ident "keyParam"
    valParam = ident "valParam"
    keyId = ident "key"
    valId = ident "val"
  var
    converterCode = newStmtList()
    accessorCode = newStmtList()
    initCode = nnkCaseStmt.newTree((quote do: $`arg`[0]))
    fieldPairsCode = nnkWhenStmt.newTree()
  def.withNodes(nnkRecCase):
    let
      recCase = parent[childIndex]
      discriminator = recCase[0]
    doAssert discriminator.kind == nnkIdentDefs
    let
      origId = discriminator[0]
      (origName, fieldIsExported) = origId.splitId()
      OrigTyp = discriminator[1]
    if OrigTyp.kind != nnkIdent:
      continue

    let
      PatchedTyp = nskType.genSym $OrigTyp
      PatchedId = makeId(PatchedTyp, fieldIsExported)
      toOrigId = makeId(nskConverter.genSym "toOrig" & $OrigTyp, typIsExported)
      toPatchedName = ident repr nskConverter.genSym $OrigTyp
      toPatchedId = makeId(toPatchedName, fieldIsExported)
    converterCode.add quote do:
      when not isSupportedAsDiscriminator(`OrigTyp`):
        type `PatchedId` = `OrigTyp`.withZeroField()

        converter `toOrigId`(x: `PatchedTyp`): `OrigTyp` {.used.} =
          doAssert x.int != 0, "default init not allowed for " & $`OrigTyp`
          cast[`OrigTyp`](x)

        converter `toPatchedId`(x: `OrigTyp`): `PatchedTyp` {.used.} =
          cast[`PatchedTyp`](x)

    let
      patchedName = ident repr nskField.genSym $origName
      origNameStr = newStrLitNode($origName)
      origNamePragma = nnkPragma.newTree(nnkExprColonExpr.newTree(
        bindSym "originalFieldName", origNameStr))
    var patchedRecCase = nnkRecCase.newTree(
      nnkIdentDefs.newTree(
        nnkPragmaExpr.newTree(patchedName, origNamePragma),
        PatchedTyp, newEmptyNode()),
      nnkOfBranch.newTree(quote do: default(`PatchedTyp`), newNilLit()))
    for i, node in recCase:
      if i == 0:
        doAssert node.kind == nnkIdentDefs
      else:
        patchedRecCase.add node
    parent[childIndex] = nnkRecWhen.newTree(
      nnkElifBranch.newTree(
        quote do: not isSupportedAsDiscriminator(`OrigTyp`),
        nnkRecList.newTree(patchedRecCase)),
      nnkElse.newTree(
        nnkRecList.newTree(recCase)))

    accessorCode.add quote do:
      when not isSupportedAsDiscriminator(`OrigTyp`):
        template `origId`(x: `T`): `OrigTyp` {.used.} =
          x.`patchedName`

        template `origId`(x: typedesc[`T`]): typedesc {.used.} =
          `OrigTyp`

    let
      patchedNameStr = newStrLitNode($patchedName)
      toPatchedNameStr = newStrLitNode($toPatchedName)
    initCode.add nnkOfBranch.newTree(origNameStr, quote do:
      when not isSupportedAsDiscriminator(`OrigTyp`):
        let staticConvert = newCall(
          ident "static", newCall(ident `toPatchedNameStr`, `arg`[1]))
        `code`.add nnkExprColonExpr.newTree(ident `patchedNameStr`,
          nnkWhenStmt.newTree(
            nnkElifExpr.newTree(
              newCall(ident "compiles", staticConvert),
              nnkPar.newTree(staticConvert)),
            nnkElse.newTree(`arg`[1])))
      else:
        `code`.add nnkExprColonExpr.newTree(`arg`[0], `arg`[1]))
    fieldPairsCode.add nnkElifBranch.newTree(
      quote do: `keyId` == `patchedNameStr`,
      quote do:
        when not isSupportedAsDiscriminator(`OrigTyp`):
          const `keyParam` {.inject, used.} = `origNameStr`
          template `valParam`: `OrigTyp` {.inject, used.} = `valId`
        else:
          {.error: `patchedNameStr` & " should not require patching".})
  initCode.add nnkElse.newTree quote do:
    `code`.add nnkExprColonExpr.newTree(`arg`[0], `arg`[1])
  fieldPairsCode.add nnkElse.newTree quote do:
    const `keyParam` {.inject, used.} = `keyId`
    template `valParam`: untyped {.inject, used.} = `valId`

  nnkTypeSection.newTree(
    nnkTypeDef.newTree(
      nskType.genSym "",
      newEmptyNode(),
      nnkStmtListType.newTree(
        converterCode,
        nnkTypeSection.newTree(typ),
        accessorCode,
        (quote do:
          macro `initId`(
              t: typedesc[`T`],
              args: varargs[untyped]{nkArgList}): `T` {.used.} =
            var `code` = nnkObjConstr.newTree(t)
            for `arg` in args:
              if `arg`.kind != nnkExprEqExpr:
                error "arguments must be passed by key", `arg`
              `initCode`
            `code`

          iterator `fieldPairsId`[t: `T`](
              x: t,
          ): tuple[key: string, val: RootObj] {.noSideEffect, used.} =
            {.error: $t & " does not support `fieldPairs`; " &
              "use `withFieldPairs` instead".}

          template `doWithFieldPairs`(
              x: `T`, `keyParam`: untyped, `valParam`: untyped,
              body: untyped) {.used.} =
            for `keyId`, `valId` in system.fieldPairs(x):
              `fieldPairsCode`
              body

          iterator `fieldsId`[t: `T`](x: t): RootObj {.noSideEffect, used.} =
            {.error: $t & " does not support `fields`; " &
              "use `withFields` instead".}

          template `doWithFields`(
              x: `T`, `valParam`: untyped,
              body: untyped) {.used.} =
            `doWithFieldPairs`(x, _, `valParam`):
              body

          func `dollarId`(x: `T`): string {.used.} =
            var
              res = "("
              didAdd = false
            x.`doWithFieldPairs`(key, val):
              if didAdd:
                res &= ", "
              res &= key & ": " & $val
              didAdd = true
            res &= ")"
            res
        ),
        ident "void")))

template withFieldPairs*(
    x: auto, keyParam: untyped, valParam: untyped, body: untyped) =
  when compiles(doWithFieldPairs(x, keyParam, valParam, body)):
    doWithFieldPairs(x, keyParam, valParam, body)
  else:
    for key, val in x.fieldPairs:
      const keyParam {.inject, used.} = key
      template valParam: untyped {.inject, used.} = val
      body

template withFields*(
    x: auto, valParam: untyped, body: untyped) =
  when compiles(doWithFields(x, valParam, body)):
    doWithFields(x, valParam, body)
  else:
    for val in fieldPairs:
      template valParam: untyped {.inject, used.} = val
      body
