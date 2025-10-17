{.push raises: [], gcsafe.}

import
  stew/shims/[tables, sets],
  ./serializer

export tables, sets

type TableType = OrderedTable | Table

proc writeValue*(w: var SerWriter, value: TableType) {.raises: [IOError].} =
  writeHead(w, SerKind.Map, value.len.uint64)
  for key, val in value:
    w.writeValue(key)
    w.writeValue(val)

proc readValue*(r: var SerReader, value: var TableType) {.raises: [IOError, SerializationError].} =
  type KeyType = typeof(value.keys)
  type ValueType = typeof(value.values)
  value = init TableType
  consumeKind r, SerKind.Map
  for _ in 0 ..< r.readUint64():
    value[readValue(r, KeyType)] = readValue(r, ValueType)

type SetType = OrderedSet | HashSet | set

proc writeValue*(w: var SerWriter, value: SetType) {.raises: [IOError].} =
  writeHead(w, SerKind.Array, value.len.uint64)
  for x in value:
    w.writeValue(x)

proc readValue*(r: var SerReader, value: var SetType) {.raises: [IOError, SerializationError].} =
  type ElemType = typeof(value.items)
  value = init SetType
  consumeKind r, SerKind.Array
  for _ in 0 ..< r.readUint64():
    value.incl readValue(r, ElemType)
