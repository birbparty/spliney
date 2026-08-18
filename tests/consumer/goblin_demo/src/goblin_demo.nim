import std/os

import raylib

import spliney
import spliney/backends/raylib/renderer

if paramCount() != 1:
  quit "usage: goblin_demo <g0bl1ntest.riv>"

let imported = loadRiveFile(paramStr(1), "g0bl1ntest.riv")
doAssert imported.isOk, imported.error.message

setConfigFlags(flags(WindowHidden))
initWindow(960, 540, "Independent Spliney consumer")
var resources: SplineyResult[PreparedResources]
var target: RenderTexture2D
try:
  let factory = newRaylibFactory()
  resources = imported.value.prepareResources(factory)
  doAssert resources.isOk, resources.error.message
  doAssert factory.decodeCount == 13 and factory.uploadCount == 13
  target = loadRenderTexture(960, 540)
  let renderer = newRaylibRenderer()
  var scene = imported.value.newScene(0, 0).value
  doAssert scene.initialSettle().isOk
  for animationIndex in 0 .. 2:
    if animationIndex > 0:
      doAssert scene.replaceAnimation(animationIndex).isOk
    for frame in 0 ..< 10:
      discard frame
      doAssert scene.advanceAndApply(0.05).isOk
      renderer.reset()
      textureMode(target):
        clearBackground(Color(r: 245, g: 247, b: 250, a: 255))
        let drawn = scene.draw(resources.value, renderer,
          Rect(minX: 0, minY: 0, maxX: 960, maxY: 540))
        doAssert drawn.isOk, drawn.error.message
  doAssert scene.close().isOk
  doAssert scene.close().isOk
finally:
  if target.texture.id != 0:
    target = default(RenderTexture2D)
  if resources.isOk:
    doAssert resources.value.close().isOk
    doAssert resources.value.close().isOk
  closeWindow()

doAssert imported.value.close().isOk
doAssert imported.value.close().isOk
echo "independent public Spliney consumer verified"
