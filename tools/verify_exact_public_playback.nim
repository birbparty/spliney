## End-to-end public-facade verifier for the private exact playback slice.

import std/os

import spliney
import spliney/backends/noop/recording

type
  CountingImage = ref object of NoOpRenderImage
  CountingFactory = ref object of NoOpFactory
    prepared, released: int

proc uint32Be(bytes: openArray[byte]; offset: int): uint32 =
  (bytes[offset].uint32 shl 24) or (bytes[offset + 1].uint32 shl 16) or
    (bytes[offset + 2].uint32 shl 8) or bytes[offset + 3].uint32

method prepareEmbeddedPng(factory: CountingFactory; assetIndex: uint32;
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
  let image = CountingImage(assetIndex: assetIndex)
  image.configureImage(expectedWidth.int, expectedHeight.int)
  ok[PreparedImage](image)

method releasePreparedImage(factory: CountingFactory;
    image: PreparedImage): SplineyStatus =
  doAssert not image.isNil
  inc factory.released
  okStatus()

if paramCount() != 1:
  quit "usage: verify_exact_public_playback <exact.riv>"

let imported = loadRiveFile(paramStr(1), "g0bl1ntest.riv")
doAssert imported.isOk, imported.error.message
let info = imported.value.defaultArtboard()
doAssert info.isOk, info.error.message
doAssert info.value.name == "Artboard"
doAssert info.value.bounds == Rect(minX: 0, minY: 0, maxX: 500, maxY: 500)
doAssert info.value.animations.len == 3
doAssert info.value.animations[0].name == "Timeline 1"
doAssert info.value.animations[0].fps == 24
doAssert info.value.animations[0].durationFrames == 192
doAssert info.value.animations[0].speed == 2
doAssert info.value.animations[0].loopValue == 1
doAssert info.value.animations[1].name == "Timeline 2"
doAssert info.value.animations[2].name == "Timeline 3"

let factory = CountingFactory()
let resources = imported.value.prepareResources(factory)
doAssert resources.isOk, resources.error.message
doAssert factory.prepared == 13

let first = imported.value.newScene(0, 0)
let second = imported.value.newScene(0, 0)
let third = imported.value.newScene(0, 2)
doAssert first.isOk, first.error.message
doAssert second.isOk, second.error.message
doAssert third.isOk, third.error.message
doAssert first.value.initialSettle().isOk
doAssert second.value.initialSettle().isOk
doAssert third.value.initialSettle().isOk
doAssert first.value.advanceAndApply(0.1).isOk
doAssert second.value.advanceAndApply(0.05).isOk
doAssert third.value.advanceAndApply(0.025).isOk

var replaceable = first.value
let invalidReplacement = replaceable.replaceAnimation(99)
doAssert not invalidReplacement.isOk
doAssert replaceable.advanceAndApply(0.1).isOk
doAssert replaceable.replaceAnimation(1).isOk
doAssert replaceable.advanceAndApply(0.1).isOk
doAssert factory.prepared == 13

let renderer = newNoOpRenderer()
let drawn = replaceable.draw(resources.value, renderer,
  Rect(minX: 0, minY: 0, maxX: 960, maxY: 540))
doAssert drawn.isOk, drawn.error.message
doAssert renderer.stackDepth == 0
doAssert renderer.invariantErrors.len == 0
var pathCount, meshCount, imageCount: int
for command in renderer.commands:
  case command.kind
  of RecordedCommandKind.drawPath: inc pathCount
  of RecordedCommandKind.drawImageMesh: inc meshCount
  of RecordedCommandKind.drawImage: inc imageCount
  else: discard
doAssert pathCount == 1
doAssert meshCount == 3
doAssert imageCount > 0

let prematureClose = imported.value.close()
doAssert not prematureClose.isOk
doAssert prematureClose.error.category == ErrorCategory.lifecycle
doAssert replaceable.close().isOk
doAssert replaceable.close().isOk
doAssert second.value.close().isOk
doAssert third.value.close().isOk
doAssert resources.value.close().isOk
doAssert resources.value.close().isOk
doAssert factory.released == 13
doAssert imported.value.close().isOk
doAssert imported.value.close().isOk
echo "exact public playback and lifecycle contract verified"
