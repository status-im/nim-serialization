import stew/shims/macros

export macros

# Helpers that can unpack `varargs[untyped]` that turn template parameters into
# function parameters - the parameters are passed on as-is using `auto` as type
# TODO what about `var`?

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

macro noxcannotraisey*(prc: untyped): untyped =
  # Using `{.pragma: noraiseshint, ....}` doesn't work in a template because of module
  # export issues
  when (NimMajor, NimMinor) >= (2, 0):
    if prc.pragma.kind == nnkEmpty:
      prc.pragma = nnkPragma.newTree()

    prc.pragma.add nnkExprColonExpr.newTree(
      nnkBracketExpr.newTree(ident "hint", ident"XCannotRaiseY"), ident"off"
    )

  prc

macro noproveinit*(prc: untyped): untyped =
  # Using `{.pragma: noraiseshint, ....}` doesn't work in a template because of module
  # export issues
  when (NimMajor, NimMinor) >= (2, 0):
    if prc.pragma.kind == nnkEmpty:
      prc.pragma = nnkPragma.newTree()

    prc.pragma.add nnkExprColonExpr.newTree(
      nnkBracketExpr.newTree(ident "warning", ident"ProveInit"), ident"off"
    )

  prc

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
      prc.params.add nnkIdentDefs.newTree(ident $arg[0], nnkCall.newTree(ident "typeof", arg[1]), newEmptyNode())
    else:
      prc.params.add nnkIdentDefs.newTree(ident "fwd" & $i, nnkCall.newTree(ident "typeof", arg[0]), newEmptyNode())
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
