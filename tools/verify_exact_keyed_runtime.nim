## Private-asset verifier for the exact keyed-animation import slice.

import std/[json, os, strformat]

import spliney/animation/engine/linear
import spliney/animation/keyed/runtime
import spliney/io/loader
import spliney/scene/artboard

if paramCount() notin 1 .. 2:
  quit "usage: verify_exact_keyed_runtime <exact.riv> [official-oracle.json]"

let path = paramStr(1)
let raw = readFile(path)
let loaded = if raw.len == 0: loadRiveWire([], path) else:
  loadRiveWire(raw.toOpenArrayByte(0, raw.high), path)
if not loaded.isOk:
  quit &"wire load failed: {loaded.error.message}"
let imported = importKeyedAnimations(loaded.value)
if not imported.isOk:
  quit &"keyed import failed: {imported.error.message}"
let linearAnimations = importLinearAnimations(loaded.value)
if not linearAnimations.isOk:
  quit &"linear animation import failed: {linearAnimations.error.message}"
let artboards = importArtboards(loaded.value)
if not artboards.isOk:
  quit &"artboard import failed: {artboards.error.message}"

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
doAssert linearAnimations.value.len == 3
doAssert artboards.value.len == 1
echo &"artboard component count: {artboards.value[0].componentCount}"
doAssert artboards.value[0].componentCount == 229
for objectId in [9'u32, 14, 16, 23, 111, 112, 141]:
  let wireIndex = artboards.value[0].componentWireIndices[objectId.int]
  echo &"  object {objectId}: wire={wireIndex} " &
    &"type={loaded.value.objects[wireIndex.int].typeKey}"
doAssert linearAnimations.value[0].name == "Timeline 1"
doAssert linearAnimations.value[0].fps == 24
doAssert linearAnimations.value[0].durationFrames == 192
doAssert linearAnimations.value[0].speed == 2
doAssert linearAnimations.value[0].loopMode == LoopMode.loop
doAssert linearAnimations.value[1].name == "Timeline 2"
doAssert linearAnimations.value[1].fps == 60
doAssert linearAnimations.value[1].durationFrames == 32
doAssert linearAnimations.value[1].speed == 1
doAssert linearAnimations.value[1].loopMode == LoopMode.loop
doAssert linearAnimations.value[2].name == "Timeline 3"
doAssert linearAnimations.value[2].fps == 60
doAssert linearAnimations.value[2].durationFrames == 32
doAssert linearAnimations.value[2].speed == 1
doAssert linearAnimations.value[2].loopMode == LoopMode.loop
doAssert objectCount == 20
doAssert propertyCount == 51
doAssert frameCount == 173
echo &"exact keyed runtime verified: animations={imported.value.len} " &
  &"objects={objectCount} properties={propertyCount} frames={frameCount}"
for animation in linearAnimations.value:
  echo &"  {animation.name}: fps={animation.fps} " &
    &"duration={animation.durationFrames} speed={animation.speed} " &
    &"loop={animation.loopMode} workArea={animation.enableWorkArea} " &
    &"[{animation.workStart}, {animation.workEnd}]"

if paramCount() == 2:
  let oracle = parseFile(paramStr(2))
  let absoluteTolerance = oracle["tolerance"]["absolute"].getFloat
  let relativeTolerance = oracle["tolerance"]["relative"].getFloat

  proc verifyState(instance: ArtboardInstance; state: JsonNode) =
    proc verifyNumber(actual: float32; expected: JsonNode; label: string) =
      let wanted = expected.getFloat
      let tolerance = absoluteTolerance + relativeTolerance * abs(wanted)
      doAssert abs(actual.float64 - wanted) <= tolerance,
        &"{label}: actual={actual} expected={wanted} tolerance={tolerance}"

    proc verifyMatrix(actual: array[6, float32]; expected: JsonNode;
        label: string) =
      for index in 0 .. 5:
        verifyNumber(actual[index], expected[index], &"{label}[{index}]")

    for expected in state["animatedProperties"]:
      let objectId = expected["objectId"].getInt.uint32
      let propertyKey = expected["propertyKey"].getInt.uint32
      let actual = instance.animatedFloat(objectId, propertyKey)
      doAssert actual.isOk, actual.error.message
      verifyNumber(actual.value, expected["value"],
        &"animated property object={objectId} property={propertyKey}")

    for expected in state["transforms"]:
      let objectId = expected["objectId"].getInt
      let component = instance.exact.components[objectId]
      verifyMatrix(component.worldTransform.values, expected["world"],
        &"world transform object={objectId}")

    for expected in state["constraints"]:
      let objectId = expected["objectId"].getInt
      let component = instance.exact.components[objectId]
      verifyNumber(component.strength, expected["strength"],
        &"constraint strength object={objectId}")
      verifyMatrix(component.parent.worldTransform.values,
        expected["parentWorld"], &"constraint parent object={objectId}")
      verifyMatrix(component.target.worldTransform.values,
        expected["targetWorld"], &"constraint target object={objectId}")

    doAssert state["solverObjects"].len == 199
    for expected in state["solverObjects"]:
      let objectId = expected["objectId"].getInt
      let component = instance.exact.components[objectId]
      doAssert component.typeKey == expected["typeKey"].getInt.uint32
      doAssert component.parentId == expected["parentId"].getInt.uint32
      case expected["kind"].getStr
      of "mesh":
        let skinId = if component.skin.isNil: 0'u32 else: component.skin.objectId
        doAssert skinId == expected["skinId"].getInt.uint32
      of "skin":
        let bindValues = component.bindTransform.values
        verifyMatrix([bindValues[0], bindValues[2], bindValues[1], bindValues[3],
          bindValues[4], bindValues[5]],
          expected["bind"],
          &"skin bind object={objectId}")
      of "tendon":
        doAssert component.boneId == expected["boneId"].getInt.uint32
        verifyMatrix(component.inverseBind.values, expected["inverseBind"],
          &"tendon inverse bind object={objectId}")
      of "contourMeshVertex":
        verifyNumber(component.vertexX, expected["position"][0],
          &"vertex x object={objectId}")
        verifyNumber(component.vertexY, expected["position"][1],
          &"vertex y object={objectId}")
        verifyNumber(component.u, expected["uv"][0], &"vertex u object={objectId}")
        verifyNumber(component.v, expected["uv"][1], &"vertex v object={objectId}")
      of "weight":
        doAssert component.weightValues == expected["values"].getInt.uint32
        doAssert component.weightIndices == expected["indices"].getInt.uint32
        verifyNumber(component.parent.renderTranslation.x,
          expected["translation"][0], &"deformed x object={objectId}")
        verifyNumber(component.parent.renderTranslation.y,
          expected["translation"][1], &"deformed y object={objectId}")
      else:
        doAssert false, "unknown solver object kind"

  for animationIndex in 0 ..< oracle["animations"].len:
    let animationOracle = oracle["animations"][animationIndex]
    let cloned = artboards.value[0].cloneArtboard(animationIndex)
    doAssert cloned.isOk, cloned.error.message
    doAssert cloned.value.initialSettle().isOk
    cloned.value.verifyState(animationOracle["states"][0])
    var remaining = animationOracle["targetSeconds"].getFloat.float32
    while remaining > 0:
      let delta = min(0.1'f32, remaining)
      doAssert cloned.value.advanceAndApply(delta).isOk
      remaining -= delta
      if remaining < 0.0000001'f32: remaining = 0
    cloned.value.verifyState(animationOracle["states"][1])
  echo "official animated-property oracle verified at start and bounded target states"
