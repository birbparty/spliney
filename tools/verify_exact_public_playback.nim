## End-to-end public-facade verifier for the private exact playback slice.

import std/os

import spliney

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

let prematureClose = imported.value.close()
doAssert not prematureClose.isOk
doAssert prematureClose.error.category == ErrorCategory.lifecycle
doAssert replaceable.close().isOk
doAssert replaceable.close().isOk
doAssert second.value.close().isOk
doAssert third.value.close().isOk
doAssert imported.value.close().isOk
doAssert imported.value.close().isOk
echo "exact public playback and lifecycle contract verified"
