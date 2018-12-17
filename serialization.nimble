mode = ScriptMode.Verbose

packageName   = "serialization"
version       = "0.1.0"
author        = "Status Research & Development GmbH"
description   = "A modern and extensible serialization framework for Nim"
license       = "Apache License 2.0"
skipDirs      = @["tests"]

requires "nim >= 0.19.0",
         "faststreams",
         "std_shims"
