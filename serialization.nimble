mode = ScriptMode.Verbose

packageName   = "serialization"
version       = "0.1.0"
author        = "Status Research & Development GmbH"
description   = "A modern and extensible serialization framework for Nim"
license       = "Apache License 2.0"
skipDirs      = @["tests"]

requires "nim >= 1.2.0",
         "faststreams",
         "stew"

task test, "Run all tests":
  exec "nim c -r --threads:off tests/test_all"
  exec "nim c -r --threads:on tests/test_all"
