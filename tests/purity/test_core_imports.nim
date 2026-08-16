import std/[algorithm, os, strutils, unittest]

const
  PureModules = [
    "spliney.nim",
    "spliney/animation/engine/linear.nim",
    "spliney/animation/interp/easing.nim",
    "spliney/animation/keyed/runtime.nim",
    "spliney/backends/noop/recording.nim",
    "spliney/contracts.nim",
    "spliney/core/transform/node.nim",
    "spliney/errors.nim",
    "spliney/generated/wire_registry.nim",
    "spliney/io/format.nim",
    "spliney/io/loader.nim",
    "spliney/math/geometry.nim",
    "spliney/render/protocol.nim",
    "spliney/scene/artboard.nim",
    "spliney/scene/dependency.nim",
    "spliney/scene/exact_runtime.nim"]
  AdapterModules = [
    "spliney/adapters/raylib_images.nim",
    "spliney/backends/raylib/renderer.nim"]

proc importSegments(body: string): seq[string] =
  var depth = 0
  var start = 0
  for index, character in body:
    case character
    of '[': inc depth
    of ']': dec depth
    of ',':
      if depth == 0:
        result.add body[start ..< index].strip
        start = index + 1
    else: discard
  result.add body[start .. ^1].strip

proc importedModule(segment: string): string =
  let words = segment.splitWhitespace()
  if words.len == 0: "" else: words[0]

proc isAllowed(module: string): bool =
  module.startsWith("std/") or module.startsWith("spliney/") or
    module in ["vmath", "bumpy"]

proc validateImports(path: string) =
  let lines = path.readFile.splitLines
  for lineNumber in 0 ..< lines.len:
    let original = lines[lineNumber]
    let line = original.strip
    if line.len == 0 or line.startsWith("#"): continue
    if line in ["import", "from", "include"]:
      check false
      checkpoint path & ":" & $(lineNumber + 1) &
        ": multiline imports are rejected by the purity parser"
      continue
    var modules: seq[string]
    if line.startsWith("import "):
      if line.endsWith(","):
        check false
        checkpoint path & ":" & $(lineNumber + 1) &
          ": multiline imports are rejected by the purity parser"
      for segment in line[7 .. ^1].importSegments:
        modules.add segment.importedModule
    elif line.startsWith("from "):
      let boundary = line.find(" import ")
      if boundary < 0:
        check false
        checkpoint path & ":" & $(lineNumber + 1) & ": malformed from import"
      else:
        modules.add line[5 ..< boundary].strip
    elif line.startsWith("include "):
      for segment in line[8 .. ^1].importSegments:
        modules.add segment.importedModule
    elif " import " in line or line.startsWith("import;") or
        line.startsWith("from;") or line.startsWith("include;"):
      check false
      checkpoint path & ":" & $(lineNumber + 1) &
        ": inline import syntax is rejected by the purity parser"
    for module in modules:
      check module.len > 0
      check module.isAllowed
      if not module.isAllowed:
        checkpoint path & ":" & $(lineNumber + 1) &
          ": dependency is outside the core allowlist: " & module

suite "fail-closed core dependency purity":
  test "graphics and undeclared packages are denied":
    for dependency in ["raylib", "rlgl", "naylib", "chroma", "pixie", "boxy",
        "some_new_package"]:
      check not dependency.isAllowed
    for dependency in ["std/math", "std/[math,tables]", "spliney/contracts",
        "vmath", "bumpy"]:
      check dependency.isAllowed

  test "source inventory and imports match the explicit allowlist":
    let projectDir = currentSourcePath().parentDir.parentDir.parentDir
    let sourceDir = projectDir / "src"
    var actual: seq[string]
    for path in walkDirRec(sourceDir):
      if path.endsWith(".nim"):
        actual.add path.relativePath(sourceDir)
    actual.sort()
    var expected = @PureModules & @AdapterModules
    expected.sort()
    check actual == expected
    for relative in PureModules:
      validateImports(sourceDir / relative)

  test "renderer-neutral barrel compiles without the Nimble package path":
    let projectDir = currentSourcePath().parentDir.parentDir.parentDir
    let command = "nim check --hints:off --mm:orc --noNimblePath " &
      quoteShell(projectDir / "tests/contracts/public_consumer.nim")
    check execShellCmd(command) == 0
