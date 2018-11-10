import streams
export streams

proc encode*(Writer: type, value: auto): auto =
  # TODO: define a concept for the Writer types
  mixin init, writeValue, getOutput

  var w = Writer.init
  w.writeValue value
  return w.getOutput

