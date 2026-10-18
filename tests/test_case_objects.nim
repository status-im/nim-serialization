# nim-serialization
# Copyright (c) 2025-2026 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at https://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at https://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

{.push raises: [].}
{.used.}

import
  unittest2,
  ../serialization/case_objects,
  ./test_case_objects_helpers

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

  HoleyKind = enum
    holeyZero = 0
    holeyFive = 5

  DistinctKind = distinct HoleyKind

  DistinctCaseObject {.allowDiscriminatorsWithoutZero.} = object
    case kind: DistinctKind
    of DistinctKind(holeyZero):
      zeroData: int
    else:
      discard

  FieldNamesObject* = object
    plain: int
    exported*: int
    pragma {.requiresInit.}: int
    exportedPragma* {.requiresInit.}: int
    renamed {.originalFieldName: "original".}: int
    exportedRenamed* {.originalFieldName: "exportedOriginal".}: int

macro identFieldNames(typ: typedesc): seq[string] =
  var names: seq[string]
  for field in typ.getImpl[2][2]:
    names.add getOriginalFieldName(field[0])
  newLit names

macro recordFieldNames(typ: typedesc): seq[string] =
  var names: seq[string]
  for field in recordFields(typ):
    names.add getOriginalFieldName(field)
  newLit names

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

    let y = DistinctCaseObject.init(
      kind = DistinctKind(holeyZero),
      zeroData = 13)
    check y.zeroData == 13

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

    block:
      var keys: seq[string]
      FieldNamesObject(pragma: 0, exportedPragma: 0).withFieldPairs(k, v):
        keys.add k
      check keys == @[
        "plain", "exported", "pragma", "exportedPragma",
        "renamed", "exportedRenamed"]

  test "Iterators across modules":
    let
      x = HelperCaseObject.init(selector = helperY, yData = "hihihi")
      expected = [
        (key: "selector", typ: "HelperSelector", val: "helperY"),
        (key: "yData", typ: "string", val: "hihihi")]

    template checkIterators(x: untyped) =
      block:
        var i = 0
        x.withFields(v):
          check:
            $typeof(v) == expected[i].typ
            $v == expected[i].val
          when v is enum:
            check v == helperY
          inc i
        check i == expected.len

      block:
        var i = 0
        x.withFieldPairs(k, v):
          check:
            k == expected[i].key
            $typeof(v) == expected[i].typ
            $v == expected[i].val
          when v is enum:
            check v == helperY
          inc i
        check i == expected.len

    checkIterators x
    checkIterators hiddenCaseObject(yData = "hihihi")

    check:
      $x == "(selector: helperY, yData: hihihi)"
      formatHelperCaseObject(x) == "(selector: helperY, yData: hihihi)"

  test "Macro access":
    check FieldNamesObject.identFieldNames == @[
      "plain", "exported", "pragma", "exportedPragma",
      "original", "exportedOriginal"]
    check CaseObject.recordFieldNames == @[
      "xafaafa", "selector", "aSelector", "aaData",
      "abData", "aData", "bData"]
