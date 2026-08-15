## Private-asset verifier for the exact keyed-animation import slice.

import std/[os, strformat]

import spliney/animation/keyed/runtime
import spliney/io/loader

if paramCount() != 1:
  quit "usage: verify_exact_keyed_runtime <exact.riv>"

let path = paramStr(1)
let raw = readFile(path)
let loaded = if raw.len == 0: loadRiveWire([], path) else:
  loadRiveWire(raw.toOpenArrayByte(0, raw.high), path)
if not loaded.isOk:
  quit &"wire load failed: {loaded.error.message}"
let imported = importKeyedAnimations(loaded.value)
if not imported.isOk:
  quit &"keyed import failed: {imported.error.message}"

var objectCount = 0
var propertyCount = 0
var frameCount = 0
for animation in imported.value:
  objectCount += animation.keyedObjects.len
  for keyedObject in animation.keyedObjects:
    propertyCount += keyedObject.properties.len
    for property in keyedObject.properties:
      frameCount += property.frames.len

doAssert imported.value.len == 3
doAssert objectCount == 20
doAssert propertyCount == 51
doAssert frameCount == 173
echo &"exact keyed runtime verified: animations={imported.value.len} " &
  &"objects={objectCount} properties={propertyCount} frames={frameCount}"
