# This module will be overhauled in the future to use concepts

type
  MemoryStream* = object
    output: seq[byte]

  StringStream* = object
    output: string

  AnyStream = MemoryStream | StringStream

const
  initialStreamCapacity = 4096

# Memory stream

proc init*(s: var MemoryStream) =
  s.output = newSeqOfCap[byte](initialStreamCapacity)

proc getOutput*(s: var MemoryStream): seq[byte] =
  shallow s.output
  result = s.output

proc init*(T: type MemoryStream): T =
  init result

proc append*(s: var MemoryStream, b: byte) =
  s.output.add b

proc append*(s: var MemoryStream, c: char) =
  s.output.add byte(c)

proc append*(s: var MemoryStream, bytes: openarray[byte]) =
  s.output.add bytes

proc append*(s: var MemoryStream, chars: openarray[char]) =
  # TODO: this can be optimized
  for c in chars:
    s.output.add byte(c)

template append*(s: var MemoryStream, str: string) =
  s.append(str.toOpenArrayByte(0, str.len - 1))

# String stream

proc init*(s: var StringStream) =
  s.output = newStringOfCap(initialStreamCapacity)

proc getOutput*(s: var StringStream): string =
  shallow s.output
  result = s.output

proc init*(T: type StringStream): T =
  init result

proc append*(s: var StringStream, c: char) =
  s.output.add c

proc append*(s: var StringStream, chars: openarray[char]) =
  # TODO: Nim doesn't have add(openarray[char]) for strings
  for c in chars:
    s.output.add c

template append*(s: var StringStream, str: string) =
  s.output.add str

# Any stream

proc appendNumberImpl(s: var AnyStream, number: BiggestInt) =
  # TODO: don't allocate
  s.append $number

proc appendNumberImpl(s: var AnyStream, number: BiggestUInt) =
  # TODO: don't allocate
  s.append $number

template toBiggestRepr(i: SomeUnsignedInt): BiggestUInt =
  BiggestUInt(i)

template toBiggestRepr(i: SomeSignedInt): BiggestInt =
  BiggestInt(i)

template appendNumber*(s: var AnyStream, i: SomeInteger) =
  # TODO: specify radix/base
  appendNumberImpl(s, toBiggestRepr(i))

