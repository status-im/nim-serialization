mode = ScriptMode.Verbose

packageName   = "serialization"
version       = "0.1.0"
author        = "Status Research & Development GmbH"
description   = "A modern and extensible serialization framework for Nim"
license       = "Apache License 2.0"
skipDirs      = @["tests"]

requires "nim >= 1.2.0",
         "faststreams",
         "unittest2",
         "stew"

task test, "Run all tests":
  let common_args = "c -r -f --hints:off --skipParentCfg"
  exec "nim " & common_args & " --threads:off tests/test_all"
  exec "nim " & common_args & " --threads:on tests/test_all"
