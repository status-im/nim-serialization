# nim-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at https://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at https://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

{.push raises: [].}
{.used.}

import
  std/sets,
  unittest2,
  ../serialization/case_objects

type
  Selector* {.requiresInit.} = enum
    A = 5
    B = 20
    C = 42

  CaseObject* {.allowDiscriminatorsWithoutZero.} = object
    case xafaafa: bool
    of default(bool): discard
    else: discard

    # x: int
    case selector*: Selector
    of A:
      when 5 == 5:
        case aSelector*: Selector
        of A:
          aaData: int
        of B:
          abData: float
        of C: discard
      aData: string
    of B:
      bData*: float
    of C: discard

macro allFieldNames(typ: typedesc): HashSet[string] =
  let
    impl = typ.getImpl()
    res = nskVar.genSym "res"
  var code = newStmtList()
  code.add quote do:
    var `res`: HashSet[string]
  impl.withNodes(nnkIdentDefs):
    let
      ident = parent[childIndex][0]
      nameNode =
        case ident.kind
        of nnkPostfix:
          ident[1]
        else:
          ident
      name =
        case nameNode.kind
        of nnkPragmaExpr:
          doAssert nameNode[1][0].kind == nnkExprColonExpr
          doAssert $nameNode[1][0][0] == "originalFieldName"
          nameNode[1][0][1]
        else:
          nameNode
      nameSym = newLit $name
    code.add quote do: `res`.incl `nameSym`
  code.add quote do: `res`
  quote do: (static(block: `code`))

suite "Case objects without 0 value in discriminator":
  test "Typing":
    check:
      CaseObject.aaData is int
      CaseObject.selector is Selector

  test "Exhaustive case statement":
    case CaseObject.selector.C
    of A, B, C: check true  # No else statement needed for compilation

    case CaseObject.init(selector = Selector.A).selector
    of A, B, C: check true  # No else statement needed for compilation

  test "Initialization":
    func foo: Selector =
      B

    let x = CaseObject.init(
      selector = Selector.A,
      aData = "hihihi",
      aSelector = foo(),
      abData = 42.0)
    check:
      x.selector == A
      x.aData == "hihihi"
      x.aSelector == foo()
      x.abData == 42.0

  test "Iterators":
    let
      x = CaseObject.init(selector = A, aSelector = A, aaData = 13)
      expected = [
        (key: "xafaafa", typ: $typeof(CaseObject.xafaafa), val: "false"),
        (key: "selector", typ: $typeof(CaseObject.selector), val: "A"),
        (key: "aSelector", typ: $typeof(CaseObject.aSelector), val: "A"),
        (key: "aaData", typ: $typeof(CaseObject.aaData), val: "13"),
        (key: "aData", typ: $typeof(CaseObject.aData), val: "")]

    block:
      var i = 0
      x.withFields(v):
        check:
          $typeof(v) == expected[i].typ
          $v == expected[i].val
        inc i
      check i == expected.len

    block:
      var i = 0
      x.withFieldPairs(k, v):
        check:
          k == expected[i].key
          $typeof(v) == expected[i].typ
          $v == expected[i].val
        inc i
      check i == expected.len

  test "Macro access":
    const fieldNames = CaseObject.allFieldNames
    check fieldNames == toHashSet [
      "xafaafa", "selector", "aSelector", "aaData",
      "abData", "aData", "bData"]
