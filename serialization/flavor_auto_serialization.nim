# nim-serialization
# Copyright (c) 2025 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE))
#  * MIT license ([LICENSE-MIT](LICENSE-MIT))
# at your option.
# This file may not be copied, modified, or distributed except according to
# those terms.

import
  std/[macrocache, macros, typetraits, options]

export
  macrocache, typetraits, options,
  macros.newLit, macros.`intVal=`, macros.boolVal

macro nimSrzCalculateSignature(T: typed): untyped =
  ## Generate signature hash from given type.
  doAssert(T.typeKind == ntyTypeDesc)
  result = newLit(signatureHash(T))

func nimSrzGetTypeSignature*(T: type): string {.compileTime.} =
  ## Force the compiler to cache the instance of this generic
  ## function, and get the same signature from every where we call it.
  type TT = proc(_: T)
  nimSrzCalculateSignature(TT)

template generateAutoSerializationAddon*(FLAVOR: typed) {.dirty.} =
  func getTable(F: type FLAVOR): CacheTable {.compileTime.} =
    ## Each Flavor has its own nsrzTable, mapping signature hash to serialization flag
    const
      nsrzTable = CacheTable("nsrzTable" & typetraits.name(F))
    nsrzTable

  func getAutoSerialize(F: type FLAVOR, T: distinct type): Option[bool] {.compileTime.} =
    ## Is a type have registered automatic serialization flag?
    let
      table = F.getTable()
      sig = nimSrzGetTypeSignature(T)

    if table.hasKey(sig):
      return some(table[sig].boolVal)
    none(bool)

  func setAutoSerialize(F: type FLAVOR, T: distinct type, val: bool) {.compileTime.} =
    ## Set the automatic serialization flag for a type.
    ## User should use `automaticSerialization` template.
    var
      sig = nimSrzGetTypeSignature(T)
      table = F.getTable()
    if table.hasKey(sig):
      table[sig].intVal = if val: 1 else: 0
    else:
      table[sig] = newLit(if val: 1 else: 0)

  func typeClassOrMemberAutoSerialize*(F: type FLAVOR, TC: distinct type, TM: distinct type): bool {.compileTime.} =
    ## Check whether a type or its parent type class have automatic serialization flag.
    when not((TM is TC) or (TM is distinct and distinctBase(TM) is TC)):
      {.error: "'" & typetraits.name(TM) & "' is not member of type class '" & typetraits.name(TC) & "'".}

    let tmAuto = F.getAutoSerialize(TM)
    if tmAuto.isSome:
      return tmAuto.get

    let tcAuto = F.getAutoSerialize(TC)
    if tcAuto.isSome:
      return tcAuto.get

    false

  func typeAutoSerialize*(F: type FLAVOR, TM: distinct type): bool {.compileTime.} =
    ## Check if a type has automatic serialization flag.
    let tmv = F.getAutoSerialize(TM)
    if tmv.isSome:
      return tmv.get
    false

  template automaticSerialization*(F: type FLAVOR, T: distinct type, enable: static[bool]) =
    ## Set a single type's automatic serialization flag.
    static:
      F.setAutoSerialize(T, enable)
