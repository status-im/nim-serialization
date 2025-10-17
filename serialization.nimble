mode = ScriptMode.Verbose

packageName   = "serialization"
version       = "0.5.0"
author        = "Status Research & Development GmbH"
description   = "A modern and extensible serialization framework for Nim"
license       = "Apache License 2.0"
skipDirs      = @["tests"]

requires "nim >= 2.0.0",
         "faststreams",
         "unittest2",
         "stew"

let nimc = getEnv("NIMC", "nim") # Which nim compiler to use
let lang = getEnv("NIMLANG", "c") # Which backend (c/cpp/js)
let flags = getEnv("NIMFLAGS", "") # Extra flags for the compiler
let verbose = getEnv("V", "") notin ["", "0"]

let cfg =
  " --styleCheck:usages --styleCheck:error" &
  (if verbose: "" else: " --verbosity:0") &
  " --skipParentCfg --skipUserCfg --outdir:build --nimcache:build/nimcache -f" &
  " -d:unittest2Static -d:serializationTestAllRountrips"

proc build(args, path: string) =
  exec nimc & " " & lang & " " & cfg & " " & flags & " " & args & " " & path

proc run(args, path: string) =
  build args & " --mm:refc -r", path
  build args & " --mm:orc -r", path

task test, "Run all tests":
  for threads in ["--threads:off", "--threads:on"]:
    run threads, "tests/test_all"
