## Immutable artboard definitions and independent exact-animation instances.

import std/[math, parseutils, tables]

import spliney/animation/engine/linear
import spliney/animation/keyed/runtime
import spliney/core/transform/node
import spliney/errors
import spliney/generated/wire_registry
import spliney/io/loader
import spliney/scene/dependency
import spliney/scene/exact_runtime

type
  ArtboardDefinition* = ref object
    objectIndex*: uint32
    componentCount*: uint32
    componentWireIndices*: seq[uint32]
    name*: string
    width*, height*: float32
    wire*: WireFile
    imageAssets*: seq[EmbeddedImageDefinition]
    animations*: seq[LinearAnimationDefinition]

  MutableObjectInstance* = ref object
    objectId*: uint32
    typeKey*: uint32
    target*: CorePropertyTarget
    dependency*: DependencyComponent

  ArtboardInstance* = ref object
    definition*: ArtboardDefinition
    animationIndex*: int
    objects*: Table[uint32, MutableObjectInstance]
    registry*: CorePropertyRegistry
    solver*: DependencySolver
    animation*: LinearAnimationInstance
    exact*: ExactScene
    settled*: bool

  SceneBuildFault* {.pure.} = enum
    none
    clone
    startApply
    settle

proc artboardError(message: string; stage: ErrorStage;
    objectId = MissingObjectId; propertyKey = MissingObjectId;
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

proc stringProperty(item: WireObject; key: uint32): SplineyResult[string] =
  let lookup = item.propertyOrDefault(key)
  if not lookup.found:
    return err[string](artboardError("missing artboard string metadata",
      ErrorStage.objectStream, propertyKey = key,
      category = ErrorCategory.malformedData))
  if lookup.serialized:
    if lookup.value.kind != WireKind.stringValue:
      return err[string](artboardError("artboard string has wrong wire value",
        ErrorStage.objectStream, propertyKey = key,
        category = ErrorCategory.malformedData))
    return ok(lookup.value.dataValue)
  var value = lookup.defaultText
  if value == "''" or value == "\"\"": value = ""
  ok(value)

proc floatProperty(item: WireObject; key: uint32): SplineyResult[float32] =
  let lookup = item.propertyOrDefault(key)
  if not lookup.found:
    return err[float32](artboardError("missing artboard float metadata",
      ErrorStage.objectStream, propertyKey = key,
      category = ErrorCategory.malformedData))
  if lookup.serialized:
    if lookup.value.kind != WireKind.floatValue:
      return err[float32](artboardError("artboard float has wrong wire value",
        ErrorStage.objectStream, propertyKey = key,
        category = ErrorCategory.malformedData))
    return ok(lookup.value.floatValue)
  var value: float
  if parseFloat(lookup.defaultText, value) == 0:
    return err[float32](artboardError("artboard float default is invalid",
      ErrorStage.objectStream, propertyKey = key,
      category = ErrorCategory.malformedData))
  ok(value.float32)

proc importArtboards*(wire: WireFile):
    SplineyResult[seq[ArtboardDefinition]] =
  if wire.isNil:
    return err[seq[ArtboardDefinition]](artboardError("nil wire file",
      ErrorStage.objectStream, category = ErrorCategory.malformedData))
  let linearAnimations = importLinearAnimations(wire)
  if not linearAnimations.isOk:
    return err[seq[ArtboardDefinition]](linearAnimations.error)
  let imageAssets = importEmbeddedImages(wire)
  if not imageAssets.isOk:
    return err[seq[ArtboardDefinition]](imageAssets.error)

  var artboardIndices: seq[int]
  for index, item in wire.objects:
    if item.typeKey == 1:
      artboardIndices.add(index)
  if artboardIndices.len == 0:
    return err[seq[ArtboardDefinition]](artboardError(
      "Rive file contains no artboard", ErrorStage.defaultArtboardSelection,
      category = ErrorCategory.resolution))

  var artboards: seq[ArtboardDefinition]
  for artboardPosition, startIndex in artboardIndices:
    let finishIndex = if artboardPosition + 1 < artboardIndices.len:
      artboardIndices[artboardPosition + 1] else: wire.objects.len
    let name = wire.objects[startIndex].stringProperty(4)
    if not name.isOk: return err[seq[ArtboardDefinition]](name.error)
    let width = wire.objects[startIndex].floatProperty(7)
    if not width.isOk: return err[seq[ArtboardDefinition]](width.error)
    let height = wire.objects[startIndex].floatProperty(8)
    if not height.isOk: return err[seq[ArtboardDefinition]](height.error)
    if width.value < 0 or height.value < 0 or
        classify(width.value) in {fcNan, fcInf, fcNegInf} or
        classify(height.value) in {fcNan, fcInf, fcNegInf}:
      return err[seq[ArtboardDefinition]](artboardError(
        "invalid artboard dimensions", ErrorStage.objectStream,
        startIndex.uint32, category = ErrorCategory.malformedData))

    var animations: seq[LinearAnimationDefinition]
    var componentFinish = finishIndex
    for animation in linearAnimations.value:
      if animation.objectId.int > startIndex and
          animation.objectId.int < finishIndex:
        animations.add(animation)
        componentFinish = min(componentFinish, animation.objectId.int)
    var componentWireIndices: seq[uint32]
    for wireIndex in startIndex ..< componentFinish:
      if wire.objects[wireIndex].typeKey.inheritsFrom(10):
        componentWireIndices.add(wireIndex.uint32)
    if componentWireIndices.len == 0 or
        componentWireIndices[0] != startIndex.uint32:
      return err[seq[ArtboardDefinition]](artboardError(
        "artboard component map is invalid", ErrorStage.referenceResolution,
        startIndex.uint32, category = ErrorCategory.resolution))
    artboards.add(ArtboardDefinition(
      objectIndex: startIndex.uint32,
      componentCount: componentWireIndices.len.uint32,
      componentWireIndices: move(componentWireIndices),
      name: name.value,
      width: width.value,
      height: height.value,
      wire: wire,
      imageAssets: imageAssets.value,
      animations: animations))
  ok(artboards)

proc initialFloat(definition: ArtboardDefinition; objectId, propertyKey: uint32):
    SplineyResult[float32] =
  if objectId >= definition.componentCount:
    return err[float32](artboardError("keyed target is outside artboard",
      ErrorStage.referenceResolution, objectId, propertyKey,
      ErrorCategory.resolution))
  let item = definition.wire.objects[
    definition.componentWireIndices[objectId.int].int]
  if not item.typeKey.typeSupportsProperty(propertyKey):
    return err[float32](artboardError("keyed target does not support property",
      ErrorStage.referenceResolution, objectId, propertyKey,
      ErrorCategory.resolution))
  item.floatProperty(propertyKey)

proc cloneArtboard*(definition: ArtboardDefinition; animationIndex: int;
    fault = SceneBuildFault.none): SplineyResult[ArtboardInstance] =
  if definition.isNil:
    return err[ArtboardInstance](artboardError("nil artboard definition",
      ErrorStage.sceneClone))
  if fault == SceneBuildFault.clone:
    return err[ArtboardInstance](artboardError("injected scene clone failure",
      ErrorStage.sceneClone))
  if animationIndex < 0 or animationIndex >= definition.animations.len:
    return err[ArtboardInstance](artboardError("animation index out of range",
      ErrorStage.sceneClone))

  let registry = newCorePropertyRegistry()
  let solver = newDependencySolver()
  var objects = initTable[uint32, MutableObjectInstance]()
  var roots: seq[DependencyComponent]
  let selected = definition.animations[animationIndex]
  for keyedObject in selected.keyed.keyedObjects:
    if objects.hasKey(keyedObject.objectId):
      return err[ArtboardInstance](artboardError(
        "duplicate keyed object group", ErrorStage.referenceResolution,
        keyedObject.objectId))
    if keyedObject.objectId >= definition.componentCount:
      return err[ArtboardInstance](artboardError(
        "keyed target is outside artboard", ErrorStage.referenceResolution,
        keyedObject.objectId, category = ErrorCategory.resolution))
    let wireObject = definition.wire.objects[
      definition.componentWireIndices[keyedObject.objectId.int].int]
    let dependency = newDependencyComponent(keyedObject.objectId)
    let target = newCorePropertyTarget(keyedObject.objectId,
      wireObject.typeKey, dependency)
    for property in keyedObject.properties:
      let initial = definition.initialFloat(keyedObject.objectId,
        property.propertyKey)
      if not initial.isOk:
        return err[ArtboardInstance](initial.error)
      let registered = target.registerStoredFloatProperty(
        property.propertyKey, initial.value)
      if not registered.isOk:
        return err[ArtboardInstance](registered.error)
    let registeredTarget = registry.registerTarget(target)
    if not registeredTarget.isOk:
      return err[ArtboardInstance](registeredTarget.error)
    objects[keyedObject.objectId] = MutableObjectInstance(
      objectId: keyedObject.objectId,
      typeKey: wireObject.typeKey,
      target: target,
      dependency: dependency)
    roots.add(dependency)

  let sorted = solver.sortDependencies(roots)
  if not sorted.isOk:
    return err[ArtboardInstance](sorted.error)
  let animation = newLinearAnimationInstance(selected, registry)
  if not animation.isOk:
    return err[ArtboardInstance](animation.error)
  let exact = newExactScene(definition.wire, definition.componentWireIndices,
    definition.imageAssets)
  if not exact.isOk:
    return err[ArtboardInstance](exact.error)
  ok(ArtboardInstance(
    definition: definition,
    animationIndex: animationIndex,
    objects: move(objects),
    registry: registry,
    solver: solver,
    animation: animation.value,
    exact: exact.value))

proc initialSettle*(instance: ArtboardInstance;
    fault = SceneBuildFault.none): SplineyStatus =
  if instance.isNil:
    return errStatus(artboardError("nil artboard instance",
      ErrorStage.initialSettle))
  if fault == SceneBuildFault.startApply:
    return errStatus(artboardError("injected start apply failure",
      ErrorStage.initialSettle))
  let applied = instance.animation.apply()
  if not applied.isOk:
    var failure = applied.error
    failure.stage = ErrorStage.initialSettle
    return errStatus(failure)
  instance.exact.syncAnimated(instance.registry)
  let exactSettled = instance.exact.settle()
  if not exactSettled.isOk:
    var failure = exactSettled.error
    failure.stage = ErrorStage.initialSettle
    return errStatus(failure)
  if fault == SceneBuildFault.settle:
    return errStatus(artboardError("injected dependency settle failure",
      ErrorStage.initialSettle))
  let settled = instance.solver.updateComponents()
  if not settled.isOk:
    var failure = settled.error
    failure.stage = ErrorStage.initialSettle
    return errStatus(failure)
  instance.settled = true
  okStatus()

proc advanceAndApply*(instance: ArtboardInstance; dt: float32): SplineyStatus =
  if instance.isNil or not instance.settled:
    return errStatus(artboardError("scene is not initially settled",
      ErrorStage.frameAdvance))
  if classify(dt) in {fcNan, fcInf, fcNegInf} or
      dt <= 0'f32 or dt > 0.1'f32:
    return errStatus(artboardError(
      "frame delta must satisfy finite 0 < dt <= 0.1",
      ErrorStage.frameAdvance))
  let advanced = instance.animation.advanceAndApply(dt)
  if not advanced.isOk:
    return errStatus(advanced.error)
  instance.exact.syncAnimated(instance.registry)
  let exactSettled = instance.exact.settle()
  if not exactSettled.isOk:
    return exactSettled
  let settled = instance.solver.updateComponents()
  if not settled.isOk:
    return errStatus(settled.error)
  okStatus()

proc replaceAnimation*(instance: var ArtboardInstance; animationIndex: int;
    fault = SceneBuildFault.none): SplineyStatus =
  if instance.isNil:
    return errStatus(artboardError("nil artboard instance",
      ErrorStage.sceneClone))
  let candidate = instance.definition.cloneArtboard(animationIndex, fault)
  if not candidate.isOk:
    return errStatus(candidate.error)
  let settled = candidate.value.initialSettle(fault)
  if not settled.isOk:
    return settled
  instance = candidate.value
  okStatus()

proc animatedFloat*(instance: ArtboardInstance; objectId, propertyKey: uint32):
    SplineyResult[float32] =
  if instance.isNil or not instance.objects.hasKey(objectId):
    return err[float32](artboardError("missing mutable scene object",
      ErrorStage.referenceResolution, objectId, propertyKey))
  instance.objects[objectId].target.floatValue(propertyKey)

proc poisonAnimatedValues*(instance: ArtboardInstance;
    value: float32): SplineyStatus =
  if instance.isNil:
    return errStatus(artboardError("nil artboard instance",
      ErrorStage.frameAdvance))
  for keyedObject in instance.definition.animations[
      instance.animationIndex].keyed.keyedObjects:
    let target = instance.objects[keyedObject.objectId].target
    for property in keyedObject.properties:
      let status = target.setFloatValue(property.propertyKey, value)
      if not status.isOk: return status
  okStatus()
