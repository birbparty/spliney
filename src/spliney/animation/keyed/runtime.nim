## Keyed double-animation definitions, import grouping, and property application.

import std/[math, parseutils, tables]

import spliney/animation/interp/easing
import spliney/core/transform/node
import spliney/errors
import spliney/generated/wire_registry
import spliney/io/loader
import spliney/scene/dependency

const MissingObjectId* = high(uint32)

type
  KeyFrameDoubleDefinition* = ref object
    frame*: uint32
    interpolation*: InterpolationKind
    interpolatorId*: uint32
    interpolator*: ref CubicBezier
    value*: float32

  KeyedPropertyDefinition* = ref object
    propertyKey*: uint32
    frames*: seq[KeyFrameDoubleDefinition]

  KeyedObjectDefinition* = ref object
    objectId*: uint32
    properties*: seq[KeyedPropertyDefinition]

  KeyedAnimationDefinition* = ref object
    objectId*: uint32
    keyedObjects*: seq[KeyedObjectDefinition]

  FloatGetter* = proc(): float32 {.closure.}
  FloatSetter* = proc(value: float32) {.closure.}

  FloatPropertyBinding* = object
    getter*: FloatGetter
    setter*: FloatSetter
    dirt*: ComponentDirt
    recurseDirt*: bool

  FloatPropertyCell = ref object
    value: float32

  CorePropertyTarget* = ref object
    objectId*: uint32
    typeKey*: uint32
    dependency*: DependencyComponent
    floatProperties: Table[uint32, FloatPropertyBinding]

  CorePropertyRegistry* = ref object
    targets: Table[uint32, CorePropertyTarget]

proc keyedError(message: string; objectId = MissingObjectId;
    propertyKey = MissingObjectId; stage = ErrorStage.referenceResolution;
    category = ErrorCategory.scene): SplineyError =
  SplineyError(
    category: category,
    stage: stage,
    message: message,
    context: ErrorContext(
      label: if objectId == MissingObjectId: "" else: $objectId,
      objectTypeKey: -1,
      propertyKey: if propertyKey == MissingObjectId: -1 else: propertyKey.int32,
      assetId: -1,
      animationIndex: -1))

proc typeSupportsProperty*(typeKey, propertyKey: uint32): bool =
  let property = propertyMetadata(propertyKey)
  if property.isNil:
    return false
  var current = typeKey
  while current != 0:
    if current == property.ownerTypeKey:
      return true
    let metadata = typeMetadata(current)
    if metadata.isNil:
      return false
    current = metadata.parentKey

proc newCorePropertyTarget*(objectId, typeKey: uint32;
    dependency: DependencyComponent = nil): CorePropertyTarget =
  CorePropertyTarget(
    objectId: objectId,
    typeKey: typeKey,
    dependency: dependency,
    floatProperties: initTable[uint32, FloatPropertyBinding]())

proc registerFloatProperty*(target: CorePropertyTarget; propertyKey: uint32;
    getter: FloatGetter; setter: FloatSetter; dirt = DirtNone;
    recurseDirt = false): SplineyStatus =
  if target.isNil or getter.isNil or setter.isNil:
    return errStatus(keyedError("invalid float property binding",
      propertyKey = propertyKey))
  if not target.typeKey.typeSupportsProperty(propertyKey):
    return errStatus(keyedError("target does not support property",
      target.objectId, propertyKey))
  if target.floatProperties.hasKey(propertyKey):
    return errStatus(keyedError("duplicate float property binding",
      target.objectId, propertyKey))
  target.floatProperties[propertyKey] = FloatPropertyBinding(
    getter: getter,
    setter: setter,
    dirt: dirt,
    recurseDirt: recurseDirt)
  okStatus()

proc registerStoredFloatProperty*(target: CorePropertyTarget;
    propertyKey: uint32; initialValue: float32; dirt = DirtComponents;
    recurseDirt = false): SplineyStatus =
  let cell = FloatPropertyCell(value: initialValue)
  target.registerFloatProperty(propertyKey,
    proc(): float32 = cell.value,
    proc(value: float32) = cell.value = value,
    dirt,
    recurseDirt)

proc floatValue*(target: CorePropertyTarget; propertyKey: uint32):
    SplineyResult[float32] =
  if target.isNil or not target.floatProperties.hasKey(propertyKey):
    return err[float32](keyedError("unsupported keyed float property",
      if target.isNil: MissingObjectId else: target.objectId, propertyKey))
  ok(target.floatProperties[propertyKey].getter())

proc setFloatValue*(target: CorePropertyTarget; propertyKey: uint32;
    value: float32): SplineyStatus =
  if target.isNil or not target.floatProperties.hasKey(propertyKey):
    return errStatus(keyedError("unsupported keyed float property",
      if target.isNil: MissingObjectId else: target.objectId, propertyKey))
  let binding = target.floatProperties[propertyKey]
  binding.setter(value)
  if not target.dependency.isNil and binding.dirt != DirtNone:
    discard target.dependency.addDirt(binding.dirt, binding.recurseDirt)
  okStatus()

proc bindNodeProperties*(target: CorePropertyTarget;
    node: NodeInstance): SplineyStatus =
  if target.isNil or node.isNil:
    return errStatus(keyedError("invalid Node property target"))
  if target.objectId != node.definition.objectId or
      target.typeKey != node.definition.typeKey:
    return errStatus(keyedError("Node property target identity mismatch",
      target.objectId))

  template bindProperty(key: uint32; field: untyped;
      dirtValue: ComponentDirt) =
    block:
      let status = target.registerFloatProperty(key,
        proc(): float32 = node.field,
        proc(value: float32) = node.field = value,
        dirtValue,
        true)
      if not status.isOk:
        return status

  bindProperty(13, x, DirtTransform or DirtWorldTransform)
  bindProperty(14, y, DirtTransform or DirtWorldTransform)
  bindProperty(15, rotation, DirtTransform or DirtWorldTransform)
  bindProperty(16, scaleX, DirtTransform or DirtWorldTransform)
  bindProperty(17, scaleY, DirtTransform or DirtWorldTransform)
  bindProperty(18, opacity, DirtRenderOpacity)
  okStatus()

proc newCorePropertyRegistry*(): CorePropertyRegistry =
  CorePropertyRegistry(targets: initTable[uint32, CorePropertyTarget]())

proc registerTarget*(registry: CorePropertyRegistry;
    target: CorePropertyTarget): SplineyStatus =
  if registry.isNil or target.isNil:
    return errStatus(keyedError("invalid core property target"))
  if registry.targets.hasKey(target.objectId):
    return errStatus(keyedError("duplicate core property target",
      target.objectId))
  registry.targets[target.objectId] = target
  okStatus()

proc resolveTarget*(registry: CorePropertyRegistry;
    objectId: uint32): CorePropertyTarget =
  if not registry.isNil:
    result = registry.targets.getOrDefault(objectId)

proc uintProperty(item: WireObject; key: uint32;
    missingSentinel = false): SplineyResult[uint32] =
  let lookup = item.propertyOrDefault(key)
  if not lookup.found:
    return err[uint32](keyedError("missing generated uint metadata",
      propertyKey = key, stage = ErrorStage.objectStream,
      category = ErrorCategory.malformedData))
  if lookup.serialized:
    if lookup.value.kind != WireKind.uintValue or
        lookup.value.uintValue > high(uint32).uint64:
      return err[uint32](keyedError("keyed uint has wrong wire value",
        propertyKey = key, stage = ErrorStage.objectStream,
        category = ErrorCategory.malformedData))
    return ok(lookup.value.uintValue.uint32)
  if missingSentinel and lookup.defaultText == "-1":
    return ok(MissingObjectId)
  var value: uint
  if parseUInt(lookup.defaultText, value) == 0 or value > high(uint32).uint:
    return err[uint32](keyedError("keyed uint default is invalid",
      propertyKey = key, stage = ErrorStage.objectStream,
      category = ErrorCategory.malformedData))
  ok(value.uint32)

proc floatProperty(item: WireObject; key: uint32): SplineyResult[float32] =
  let lookup = item.propertyOrDefault(key)
  if not lookup.found:
    return err[float32](keyedError("missing generated float metadata",
      propertyKey = key, stage = ErrorStage.objectStream,
      category = ErrorCategory.malformedData))
  if lookup.serialized:
    if lookup.value.kind != WireKind.floatValue:
      return err[float32](keyedError("keyed float has wrong wire value",
        propertyKey = key, stage = ErrorStage.objectStream,
        category = ErrorCategory.malformedData))
    return ok(lookup.value.floatValue)
  var value: float
  if parseFloat(lookup.defaultText, value) == 0:
    return err[float32](keyedError("keyed float default is invalid",
      propertyKey = key, stage = ErrorStage.objectStream,
      category = ErrorCategory.malformedData))
  ok(value.float32)

proc importKeyedAnimations*(file: WireFile):
    SplineyResult[seq[KeyedAnimationDefinition]] =
  if file.isNil:
    return err[seq[KeyedAnimationDefinition]](keyedError(
      "nil wire file", stage = ErrorStage.objectStream,
      category = ErrorCategory.malformedData))

  var animations: seq[KeyedAnimationDefinition]
  var currentAnimation: KeyedAnimationDefinition
  var currentObject: KeyedObjectDefinition
  var currentProperty: KeyedPropertyDefinition

  for index, item in file.objects:
    case item.typeKey
    of 31:
      currentAnimation = KeyedAnimationDefinition(objectId: index.uint32)
      animations.add(currentAnimation)
      currentObject = nil
      currentProperty = nil
    of 25:
      if currentAnimation.isNil:
        return err[seq[KeyedAnimationDefinition]](keyedError(
          "KeyedObject is outside a LinearAnimation", index.uint32,
          stage = ErrorStage.objectStream,
          category = ErrorCategory.malformedData))
      let objectId = item.uintProperty(51)
      if not objectId.isOk:
        return err[seq[KeyedAnimationDefinition]](objectId.error)
      currentObject = KeyedObjectDefinition(objectId: objectId.value)
      currentAnimation.keyedObjects.add(currentObject)
      currentProperty = nil
    of 26:
      if currentObject.isNil:
        return err[seq[KeyedAnimationDefinition]](keyedError(
          "KeyedProperty is outside a KeyedObject", index.uint32,
          stage = ErrorStage.objectStream,
          category = ErrorCategory.malformedData))
      let propertyKey = item.uintProperty(53)
      if not propertyKey.isOk:
        return err[seq[KeyedAnimationDefinition]](propertyKey.error)
      if propertyMetadata(propertyKey.value).isNil:
        return err[seq[KeyedAnimationDefinition]](keyedError(
          "unknown keyed property", currentObject.objectId,
          propertyKey.value, ErrorStage.referenceResolution,
          ErrorCategory.resolution))
      currentProperty = KeyedPropertyDefinition(propertyKey: propertyKey.value)
      currentObject.properties.add(currentProperty)
    of 30:
      if currentProperty.isNil:
        return err[seq[KeyedAnimationDefinition]](keyedError(
          "KeyFrameDouble is outside a KeyedProperty", index.uint32,
          stage = ErrorStage.objectStream,
          category = ErrorCategory.malformedData))
      let frame = item.uintProperty(67)
      if not frame.isOk:
        return err[seq[KeyedAnimationDefinition]](frame.error)
      let interpolation = item.uintProperty(68)
      if not interpolation.isOk:
        return err[seq[KeyedAnimationDefinition]](interpolation.error)
      let interpolatorId = item.uintProperty(69, missingSentinel = true)
      if not interpolatorId.isOk:
        return err[seq[KeyedAnimationDefinition]](interpolatorId.error)
      let value = item.floatProperty(70)
      if not value.isOk:
        return err[seq[KeyedAnimationDefinition]](value.error)
      if currentProperty.frames.len > 0 and
          frame.value < currentProperty.frames[^1].frame:
        return err[seq[KeyedAnimationDefinition]](keyedError(
          "keyframes are not ordered", currentObject.objectId,
          currentProperty.propertyKey, ErrorStage.referenceResolution,
          ErrorCategory.malformedData))
      currentProperty.frames.add(KeyFrameDoubleDefinition(
        frame: frame.value,
        interpolation: if interpolation.value == 0:
          InterpolationKind.hold else: InterpolationKind.interpolate,
        interpolatorId: interpolatorId.value,
        value: value.value))
    else:
      discard
  ok(animations)

proc validate*(definition: KeyedObjectDefinition;
    registry: CorePropertyRegistry): SplineyStatus =
  if definition.isNil:
    return errStatus(keyedError("nil keyed object"))
  let target = registry.resolveTarget(definition.objectId)
  if target.isNil:
    return errStatus(keyedError("missing keyed target", definition.objectId))
  for property in definition.properties:
    if property.isNil or not target.floatProperties.hasKey(property.propertyKey):
      return errStatus(keyedError("unsupported keyed float property",
        definition.objectId,
        if property.isNil: MissingObjectId else: property.propertyKey))
    if property.frames.len == 0:
      return errStatus(keyedError("keyed property has no frames",
        definition.objectId, property.propertyKey))
    for frame in property.frames:
      if frame.interpolatorId != MissingObjectId and frame.interpolator.isNil:
        return errStatus(keyedError("missing keyframe interpolator",
          definition.objectId, property.propertyKey))
  okStatus()

proc sample*(property: KeyedPropertyDefinition; seconds, fps: float32):
    SplineyResult[float32] =
  if property.isNil or property.frames.len == 0:
    return err[float32](keyedError("keyed property has no frames"))
  if fps <= 0 or classify(fps) in {fcNan, fcInf, fcNegInf}:
    return err[float32](keyedError("animation fps must be finite and positive",
      propertyKey = property.propertyKey, stage = ErrorStage.frameAdvance))
  if classify(seconds) in {fcNan, fcInf, fcNegInf}:
    return err[float32](keyedError("animation time must be finite",
      propertyKey = property.propertyKey, stage = ErrorStage.frameAdvance))
  let frameTime = seconds * fps
  var low = 0
  var high = property.frames.high
  while low <= high:
    let middle = (low + high) shr 1
    if property.frames[middle].frame.float32 < frameTime:
      low = middle + 1
    elif property.frames[middle].frame.float32 > frameTime:
      high = middle - 1
    else:
      return ok(property.frames[middle].value)
  let nextIndex = low
  if nextIndex == 0:
    return ok(property.frames[0].value)
  if nextIndex >= property.frames.len:
    return ok(property.frames[^1].value)
  let fromFrame = property.frames[nextIndex - 1]
  let toFrame = property.frames[nextIndex]
  if fromFrame.interpolation == InterpolationKind.hold:
    return ok(fromFrame.value)
  let span = (toFrame.frame - fromFrame.frame).float32
  if span <= 0:
    return ok(toFrame.value)
  let factor = (frameTime - fromFrame.frame.float32) / span
  let curve = if fromFrame.interpolator.isNil: nil else:
    addr fromFrame.interpolator[]
  ok(interpolate(fromFrame.value, toFrame.value, factor,
    fromFrame.interpolation, curve))

proc apply*(definition: KeyedObjectDefinition;
    registry: CorePropertyRegistry; seconds, fps: float32;
    mix = 1'f32): SplineyStatus =
  let valid = definition.validate(registry)
  if not valid.isOk:
    return valid
  if classify(mix) in {fcNan, fcInf, fcNegInf}:
    return errStatus(keyedError("animation mix must be finite",
      definition.objectId, stage = ErrorStage.frameAdvance))
  let target = registry.resolveTarget(definition.objectId)
  for property in definition.properties:
    let sampled = property.sample(seconds, fps)
    if not sampled.isOk:
      return errStatus(sampled.error)
    let binding = target.floatProperties[property.propertyKey]
    let value = if mix == 1: sampled.value else:
      binding.getter() * (1 - mix) + sampled.value * mix
    binding.setter(value)
    if not target.dependency.isNil and binding.dirt != DirtNone:
      discard target.dependency.addDirt(binding.dirt, binding.recurseDirt)
  okStatus()

proc apply*(definition: KeyedAnimationDefinition;
    registry: CorePropertyRegistry; seconds, fps: float32;
    mix = 1'f32): SplineyStatus =
  if definition.isNil:
    return errStatus(keyedError("nil keyed animation"))
  for keyedObject in definition.keyedObjects:
    let status = keyedObject.apply(registry, seconds, fps, mix)
    if not status.isOk:
      return status
  okStatus()
