import
  serialization/[streams, object_serialization]

export
  streams, object_serialization

proc encodeImpl(w: var auto, value: auto): auto =
  mixin writeValue, getOutput
  w.writeValue value
  return w.getOutput

template encode*(Writer: type, value: auto, params: varargs[untyped]): auto =
  mixin init, writeValue, getOutput
  var w = Writer.init(params)
  encodeImpl(w, value)

