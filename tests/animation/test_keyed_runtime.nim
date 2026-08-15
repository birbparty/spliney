import std/unittest

import spliney/animation/interp/easing
import spliney/animation/keyed/runtime
import spliney/core/transform/node
import spliney/errors
import spliney/generated/wire_registry
import spliney/io/loader
import spliney/scene/dependency

proc wireProperty(key: uint32; value: WireValue): WireProperty =
  WireProperty(key: key, value: value)

proc uintValue(value: uint64): WireValue =
  WireValue(kind: WireKind.uintValue, uintValue: value)

proc floatValue(value: float32): WireValue =
  WireValue(kind: WireKind.floatValue, floatValue: value)

proc wireObject(typeKey: uint32;
    properties: seq[WireProperty] = @[]): WireObject =
  WireObject(typeKey: typeKey, knownType: true, properties: properties)

proc nodeDefinitionForTest(): NodeDefinition =
  NodeDefinition(objectId: 7, typeKey: 2, scaleX: 1, scaleY: 1, opacity: 1)

suite "keyed property runtime":
  test "wire stream hierarchy imports exact-asset keyed double shapes":
    let file = WireFile(objects: @[
      wireObject(31),
      wireObject(25, @[wireProperty(51, uintValue(7))]),
      wireObject(26, @[wireProperty(53, uintValue(13))]),
      wireObject(30, @[
        wireProperty(68, uintValue(1)),
        wireProperty(70, floatValue(2))]),
      wireObject(30, @[
        wireProperty(67, uintValue(10)),
        wireProperty(68, uintValue(1)),
        wireProperty(70, floatValue(12))])])
    let imported = importKeyedAnimations(file)
    require imported.isOk
    check imported.value.len == 1
    check imported.value[0].objectId == 0
    check imported.value[0].keyedObjects[0].objectId == 7
    check imported.value[0].keyedObjects[0].properties[0].propertyKey == 13
    check imported.value[0].keyedObjects[0].properties[0].frames.len == 2
    check imported.value[0].keyedObjects[0].properties[0].frames[0].frame == 0
    check imported.value[0].keyedObjects[0].properties[0].frames[0].interpolatorId ==
      MissingObjectId

  test "linear hold endpoints and mix match official apply behavior":
    let linear = KeyedPropertyDefinition(propertyKey: 13, frames: @[
      KeyFrameDoubleDefinition(frame: 0,
        interpolation: InterpolationKind.interpolate,
        interpolatorId: MissingObjectId, value: 2),
      KeyFrameDoubleDefinition(frame: 10,
        interpolation: InterpolationKind.interpolate,
        interpolatorId: MissingObjectId, value: 12)])
    check linear.sample(-1, 10).value == 2
    check linear.sample(0.5, 10).value == 7
    check linear.sample(2, 10).value == 12

    let held = KeyedPropertyDefinition(propertyKey: 13, frames: @[
      KeyFrameDoubleDefinition(frame: 0,
        interpolation: InterpolationKind.hold,
        interpolatorId: MissingObjectId, value: 2),
      KeyFrameDoubleDefinition(frame: 10,
        interpolation: InterpolationKind.interpolate,
        interpolatorId: MissingObjectId, value: 12)])
    check held.sample(0.5, 10).value == 2
    check held.sample(1, 10).value == 12

  test "Core property setters mutate only the instance and propagate dirt":
    let definition = nodeDefinitionForTest()
    let node = newNodeInstance(definition)
    let dependency = newDependencyComponent(7, initialDirt = DirtNone)
    let target = newCorePropertyTarget(7, 2, dependency)
    require target.bindNodeProperties(node).isOk
    let registry = newCorePropertyRegistry()
    require registry.registerTarget(target).isOk
    let keyed = KeyedObjectDefinition(objectId: 7, properties: @[
      KeyedPropertyDefinition(propertyKey: 13, frames: @[
        KeyFrameDoubleDefinition(frame: 0,
          interpolation: InterpolationKind.interpolate,
          interpolatorId: MissingObjectId, value: 10),
        KeyFrameDoubleDefinition(frame: 10,
          interpolation: InterpolationKind.interpolate,
          interpolatorId: MissingObjectId, value: 20)])])

    node.x = 2
    require keyed.apply(registry, 0.5, 10, mix = 0.5).isOk
    check node.x == 8.5
    check definition.x == 0
    check dependency.dirt.containsAny(DirtTransform)
    check dependency.dirt.containsAny(DirtWorldTransform)

  test "target and property resolution failures are structured":
    let registry = newCorePropertyRegistry()
    let missing = KeyedObjectDefinition(objectId: 99, properties: @[
      KeyedPropertyDefinition(propertyKey: 13, frames: @[
        KeyFrameDoubleDefinition(frame: 0,
          interpolatorId: MissingObjectId, value: 1)])])
    let result = missing.apply(registry, 0, 60)
    check not result.isOk
    check result.error.category == ErrorCategory.scene
    check result.error.stage == ErrorStage.referenceResolution
    check result.error.message == "missing keyed target"

    let definition = nodeDefinitionForTest()
    let target = newCorePropertyTarget(7, 2)
    require target.bindNodeProperties(newNodeInstance(definition)).isOk
    require registry.registerTarget(target).isOk
    let unresolved = KeyedObjectDefinition(objectId: 7, properties: @[
      KeyedPropertyDefinition(propertyKey: 13, frames: @[
        KeyFrameDoubleDefinition(frame: 0, interpolatorId: 44, value: 1)])])
    let unresolvedResult = unresolved.apply(registry, 0, 60)
    check not unresolvedResult.isOk
    check unresolvedResult.error.message == "missing keyframe interpolator"

  test "malformed grouping and descending frames are rejected":
    let orphan = importKeyedAnimations(WireFile(objects: @[
      wireObject(26, @[wireProperty(53, uintValue(13))])]))
    check not orphan.isOk
    check orphan.error.stage == ErrorStage.objectStream

    let descending = importKeyedAnimations(WireFile(objects: @[
      wireObject(31),
      wireObject(25, @[wireProperty(51, uintValue(7))]),
      wireObject(26, @[wireProperty(53, uintValue(13))]),
      wireObject(30, @[
        wireProperty(67, uintValue(10)),
        wireProperty(70, floatValue(1))]),
      wireObject(30, @[
        wireProperty(67, uintValue(5)),
        wireProperty(70, floatValue(2))])]))
    check not descending.isOk
    check descending.error.message == "keyframes are not ordered"
