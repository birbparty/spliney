## Public-facade, private-fixture headless readiness gate.

import std/[os, osproc, parseopt, strutils]

import spliney
import spliney/backends/noop/recording

const ExpectedAssetSha =
  "7a2f1d58da22e12932e73e76366b48651e66d9980153ece5433188c8fd08bc35"

type
  Options = object
    assetPath: string
    requirePrivateFixture: bool

  ValidatingImage = ref object of NoOpRenderImage

  ValidatingFactory = ref object of NoOpFactory
    prepared, released: int

proc options(): Options =
  var parser = initOptParser(commandLineParams())
  while true:
    parser.next()
    case parser.kind
    of cmdEnd: break
    of cmdLongOption, cmdShortOption:
      case parser.key
      of "asset": result.assetPath = parser.val
      of "require-private-fixture": result.requirePrivateFixture = true
      else: quit "unknown option: --" & parser.key
    of cmdArgument:
      quit "unexpected argument: " & parser.key

proc sha256(path: string): string =
  let output = execProcess("shasum", args = ["-a", "256", path],
    options = {poUsePath, poStdErrToStdOut})
  let fields = output.splitWhitespace()
  if fields.len > 0: fields[0] else: ""

proc uint32Be(bytes: openArray[byte]; offset: int): uint32 =
  (bytes[offset].uint32 shl 24) or (bytes[offset + 1].uint32 shl 16) or
    (bytes[offset + 2].uint32 shl 8) or bytes[offset + 3].uint32

method prepareEmbeddedPng(factory: ValidatingFactory; assetIndex: uint32;
    name: string; compressedBytes: openArray[byte]; expectedWidth,
    expectedHeight: uint32): SplineyResult[PreparedImage] =
  doAssert name.len > 0
  doAssert compressedBytes.len >= 24
  doAssert compressedBytes[0 .. 7] ==
    [137'u8, 80, 78, 71, 13, 10, 26, 10]
  doAssert compressedBytes.uint32Be(16) == expectedWidth
  doAssert compressedBytes.uint32Be(20) == expectedHeight
  doAssert assetIndex == factory.prepared.uint32
  inc factory.prepared
  let image = ValidatingImage(assetIndex: assetIndex)
  image.configureImage(expectedWidth.int, expectedHeight.int)
  ok[PreparedImage](image)

method releasePreparedImage(factory: ValidatingFactory;
    image: PreparedImage): SplineyStatus =
  doAssert not image.isNil
  inc factory.released
  okStatus()

proc snapshot(scene: PlayableScene; resources: PreparedResources): seq[byte] =
  let renderer = newNoOpRenderer()
  let drawn = scene.draw(resources, renderer,
    Rect(minX: 0, minY: 0, maxX: 960, maxY: 540))
  doAssert drawn.isOk, drawn.error.message
  doAssert renderer.stackDepth == 0
  doAssert renderer.invariantErrors.len == 0
  var pathCount, imageCount, meshCount: int
  for command in renderer.commands:
    case command.kind
    of RecordedCommandKind.drawPath: inc pathCount
    of RecordedCommandKind.drawImage: inc imageCount
    of RecordedCommandKind.drawImageMesh: inc meshCount
    else: discard
  doAssert pathCount == 1
  doAssert imageCount > 0
  doAssert meshCount == 3
  renderer.canonicalBytes()

proc main() =
  let arguments = options()
  if arguments.assetPath.len == 0 or not fileExists(arguments.assetPath):
    if arguments.requirePrivateFixture:
      quit "required private fixture is missing", QuitFailure
    echo "[SKIP] exact goblin private fixture unavailable"
    return
  doAssert arguments.assetPath.sha256 == ExpectedAssetSha,
    "private fixture SHA-256 mismatch"

  let imported = loadRiveFile(arguments.assetPath, "g0bl1ntest.riv")
  doAssert imported.isOk, imported.error.message
  let info = imported.value.defaultArtboard()
  doAssert info.isOk, info.error.message
  doAssert info.value.name == "Artboard"
  doAssert info.value.bounds == Rect(minX: 0, minY: 0, maxX: 500, maxY: 500)
  doAssert info.value.animations.len == 3
  let names = ["Timeline 1", "Timeline 2", "Timeline 3"]
  let fps = [24'f32, 60, 60]
  let durations = [192'u32, 32, 32]
  let speeds = [2'f32, 1, 1]
  for index in 0 .. 2:
    let animation = info.value.animations[index]
    doAssert animation.index == index
    doAssert animation.name == names[index]
    doAssert animation.fps == fps[index]
    doAssert animation.durationFrames == durations[index]
    doAssert animation.speed == speeds[index]
    doAssert animation.loopValue == 1

  let factory = ValidatingFactory()
  let resources = imported.value.prepareResources(factory)
  doAssert resources.isOk, resources.error.message
  doAssert factory.prepared == 13

  let targetSeconds = [2'f32, 16'f32 / 60'f32, 16'f32 / 60'f32]
  var freshStart = newSeq[seq[byte]](3)
  for animationIndex in 0 .. 2:
    let sceneResult = imported.value.newScene(0, animationIndex)
    doAssert sceneResult.isOk, sceneResult.error.message
    let scene = sceneResult.value
    doAssert scene.initialSettle().isOk
    freshStart[animationIndex] = scene.snapshot(resources.value)
    var remaining = targetSeconds[animationIndex]
    while remaining > 0:
      let delta = min(0.1'f32, remaining)
      doAssert scene.advanceAndApply(delta).isOk
      remaining -= delta
      if remaining < 0.0000001'f32: remaining = 0
    doAssert scene.snapshot(resources.value) != freshStart[animationIndex]
    doAssert scene.close().isOk

  let first = imported.value.newScene(0, 0)
  let second = imported.value.newScene(0, 0)
  doAssert first.isOk and second.isOk
  doAssert first.value.initialSettle().isOk
  doAssert second.value.initialSettle().isOk
  doAssert first.value.advanceAndApply(0.1).isOk
  doAssert second.value.advanceAndApply(0.05).isOk
  doAssert first.value.snapshot(resources.value) !=
    second.value.snapshot(resources.value)
  doAssert first.value.close().isOk
  doAssert second.value.close().isOk

  var replaceable = imported.value.newScene(0, 0).value
  doAssert replaceable.initialSettle().isOk
  for cycle in 0 ..< 30:
    doAssert replaceable.advanceAndApply(0.1).isOk
    let selected = cycle mod 3
    doAssert replaceable.replaceAnimation(selected).isOk
    let selectedStart = replaceable.snapshot(resources.value)
    doAssert selectedStart == freshStart[selected]
    let failed = replaceable.replaceAnimation(99)
    doAssert not failed.isOk
    doAssert failed.error.category == ErrorCategory.scene
    doAssert replaceable.snapshot(resources.value) == selectedStart
    doAssert factory.prepared == 13

  doAssert replaceable.close().isOk
  doAssert resources.value.close().isOk
  doAssert resources.value.close().isOk
  doAssert factory.released == 13
  doAssert imported.value.close().isOk
  doAssert imported.value.close().isOk
  echo "exact goblin public headless gate verified"

when isMainModule:
  main()
