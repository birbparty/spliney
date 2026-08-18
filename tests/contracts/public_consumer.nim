## Compile-only external-consumer contract. This uses public exports only and
## intentionally does not execute while Gate 1+ fills in the runtime bodies.

import spliney

type
  FixtureFactory = ref object of ResourceFactory
  FixtureRenderer = ref object of RenderSink

proc compileConsumer(bytes: seq[byte]; factory: FixtureFactory;
    renderer: FixtureRenderer) =
  let imported = importRive(bytes, "consumer-fixture")
  if not imported.isOk:
    let failure: SplineyError = imported.error
    doAssert failure.context.label == "consumer-fixture"
    return

  let file = imported.value
  let artboard = defaultArtboard(file)
  if not artboard.isOk: return

  let resources = prepareResources(file, factory)
  if not resources.isOk: return
  var sceneResult = newScene(file, artboard.value.index,
    artboard.value.animations[0].index)
  if not sceneResult.isOk: return
  var scene = sceneResult.value

  discard initialSettle(scene)
  discard advanceAndApply(scene, 0.1'f32)
  discard draw(scene, resources.value, renderer,
    Rect(minX: 0, minY: 0, maxX: 960, maxY: 540),
    Vec2(x: 100, y: 0))
  discard replaceAnimation(scene, 1)

  discard close(scene)
  discard close(resources.value)
  discard close(file)
