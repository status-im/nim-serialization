type
  Base64* = object
  Base64Pad* = object
  Base64Types* = Base64 | Base64Pad

func encode*(
    btype: typedesc[Base64Types], inbytes: openArray[byte]
): string {.inline.} =
  discard
