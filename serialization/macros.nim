import stew/shims/macros

export macros

# Helpers that can unpack `varargs[untyped]` that turn template parameters into
# function parameters - the parameters are passed on as-is using `auto` as type
# TODO what about `var`?

let autoKeyword {.compileTime.} = ident"auto"

iterator usefulArgs(args: NimNode): NimNode =
  for arg in args:
    let arg =
      if arg.kind == nnkHiddenStdConv:
        arg[0]
      else:
        arg
    if arg.kind == nnkEmpty:
      continue
    yield arg

macro forward*(args, prc: untyped): untyped =
  # Add `args: varargs[untyped]` as individual parameters - if the parameters
  # are of the type `a = b`, they will be named `a`, else `fwd$i` where i is the
  # index of the parameter - see `unpackForwarded` below for how to pass them on
  # to the next call
  var i = 0
  for arg in usefulArgs(args):
    if arg.kind == nnkExprEqExpr:
      # need $ here to ensure it's a freshly looked up identifier, in case there
      # are symbol conflicts - would be nice if `unpackForwarded` could reuse
      # this exact ident instance ..
      prc.params.add nnkIdentDefs.newTree(ident $arg[0], autoKeyword, newEmptyNode())
    else:
      prc.params.add nnkIdentDefs.newTree(ident "fwd" & $i, autoKeyword, newEmptyNode())
    i += 1
  prc

macro unpackForwarded*(callee: untyped, args: untyped): untyped =
  # pass on `args` to callee - args should be an array of parameters to pass
  # on to callee where one of them should be the `varargs[untyped]` passed to
  # the forward macro. Messy.
  result = newCall(callee)
  var i = 0

  for arg in usefulArgs(args):
    if arg.kind == nnkArgList:
      for subarg in usefulArgs(arg):

        if subarg.kind == nnkExprEqExpr:
          result.add nnkExprEqExpr.newTree(ident $subarg[0], ident $subarg[0])
        else:
          result.add ident "fwd" & $i
          i += 1
    else:
      result.add arg
