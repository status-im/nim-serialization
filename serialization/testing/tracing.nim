const serialization_tracing {.strdefine.} = ""
const hasSerializationTracing* = serialization_tracing != ""

when hasSerializationTracing:
  var tracingEnabled* = serialization_tracing in ["yes", "on", "1"]

  ## TODO
  ## Implement a tracing context object that will be
  ## able to track down which object fields are currently
  ## entered. It will print the debug output in a form
  ## that can be easily collapsed with indentation-based
  ## outlining in most text editors.

  func isTracingEnabled: bool =
    # TODO this is a work-around for the lack of working
    # `{.noSideEffect.}:` override in Nim 0.19.6.
    {.emit: "`result` = `tracingEnabled`;".}

  template traceSerialization*(args: varargs[untyped]) =
    ## `traceSerialization` can be used to capture precise
    ## traces of the serialization and deserialization of
    ## complex formats.
    if isTracingEnabled():
      debugEcho args

  template trs*(args: varargs[untyped]) =
    ## `trs` is shorter form for "trace serialization"
    ## that's easy to write during active development
    ## and easy to replace with `traceSerialization`
    ## once your library is complete :)
    traceSerialization(args)

else:
  template traceSerialization*(args: varargs[untyped]) = discard
  template trs*(args: varargs[untyped]) = discard

