mode = ScriptMode.Verbose

packageName   = "serialization"
version       = "0.1.0"
author        = "Status Research & Development GmbH"
description   = "A modern extensible serialization framework for Nim"
license       = "Apache License 2.0"
skipDirs      = @["tests"]

requires "nim >= 0.19.0"

proc configForTests() =
  --hints: off
  --debuginfo
  --path: "."
  --run

task test, "run tests":
  configForTests()
  setCommand "c", "tests/all.nim"

