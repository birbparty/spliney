## Linear animation timing and keyed-property application.

import std/[math, parseutils]

import spliney/animation/keyed/runtime
import spliney/errors
import spliney/generated/wire_registry
import spliney/io/loader

type
  LoopMode* {.pure.} = enum
    oneShot = 0
    loop = 1
    pingPong = 2

  LinearAnimationDefinition* = ref object
    objectId*: uint32
    name*: string
    fps*: uint32
    durationFrames*: uint32
    speed*: float32
    loopMode*: LoopMode
    workStart*, workEnd*: uint32
    enableWorkArea*: bool
    quantize*: bool
    keyed*: KeyedAnimationDefinition

  LinearAnimationInstance* = ref object
    definition*: LinearAnimationDefinition
    registry*: CorePropertyRegistry
    time*: float32
    direction*: float32
    totalTime*: float32
    lastTotalTime*: float32
    spilledTime*: float32
    didLoop*: bool
    loopOverride: int32

proc animationError(message: string; animationId = MissingObjectId;
    propertyKey = MissingObjectId; stage = ErrorStage.referenceResolution;
    category = ErrorCategory.scene): SplineyError =
  SplineyError(
    category: category,
    stage: stage,
    message: message,
    context: ErrorContext(
      label: if animationId == MissingObjectId: "" else: $animationId,
      objectTypeKey: 31,
      propertyKey: if propertyKey == MissingObjectId: -1 else: propertyKey.int32,
      assetId: -1,
      animationIndex: -1))

proc uintProperty(item: WireObject; key: uint32;
    missingSentinel = false): SplineyResult[uint32] =
  let lookup = item.propertyOrDefault(key)
  if not lookup.found:
    return err[uint32](animationError("missing animation uint metadata",
      propertyKey = key, stage = ErrorStage.objectStream,
      category = ErrorCategory.malformedData))
  if lookup.serialized:
    if lookup.value.kind != WireKind.uintValue or
        lookup.value.uintValue > high(uint32).uint64:
      return err[uint32](animationError("animation uint has wrong wire value",
        propertyKey = key, stage = ErrorStage.objectStream,
        category = ErrorCategory.malformedData))
    return ok(lookup.value.uintValue.uint32)
  if missingSentinel and lookup.defaultText == "-1":
    return ok(MissingObjectId)
  var value: uint
  if parseUInt(lookup.defaultText, value) == 0 or value > high(uint32).uint:
    return err[uint32](animationError("animation uint default is invalid",
      propertyKey = key, stage = ErrorStage.objectStream,
      category = ErrorCategory.malformedData))
  ok(value.uint32)

proc floatProperty(item: WireObject; key: uint32): SplineyResult[float32] =
  let lookup = item.propertyOrDefault(key)
  if not lookup.found:
    return err[float32](animationError("missing animation float metadata",
      propertyKey = key, stage = ErrorStage.objectStream,
      category = ErrorCategory.malformedData))
  if lookup.serialized:
    if lookup.value.kind != WireKind.floatValue:
      return err[float32](animationError("animation float has wrong wire value",
        propertyKey = key, stage = ErrorStage.objectStream,
        category = ErrorCategory.malformedData))
    return ok(lookup.value.floatValue)
  var value: float
  if parseFloat(lookup.defaultText, value) == 0:
    return err[float32](animationError("animation float default is invalid",
      propertyKey = key, stage = ErrorStage.objectStream,
      category = ErrorCategory.malformedData))
  ok(value.float32)

proc stringProperty(item: WireObject; key: uint32): SplineyResult[string] =
  let lookup = item.propertyOrDefault(key)
  if not lookup.found:
    return err[string](animationError("missing animation string metadata",
      propertyKey = key, stage = ErrorStage.objectStream,
      category = ErrorCategory.malformedData))
  if lookup.serialized:
    if lookup.value.kind != WireKind.stringValue:
      return err[string](animationError("animation string has wrong wire value",
        propertyKey = key, stage = ErrorStage.objectStream,
        category = ErrorCategory.malformedData))
    return ok(lookup.value.dataValue)
  var value = lookup.defaultText
  if value == "''" or value == "\"\"":
    value = ""
  ok(value)

proc boolProperty(item: WireObject; key: uint32): SplineyResult[bool] =
  let lookup = item.propertyOrDefault(key)
  if not lookup.found:
    return err[bool](animationError("missing animation bool metadata",
      propertyKey = key, stage = ErrorStage.objectStream,
      category = ErrorCategory.malformedData))
  if lookup.serialized:
    if lookup.value.kind != WireKind.uintValue or lookup.value.uintValue > 1:
      return err[bool](animationError("animation bool has wrong wire value",
        propertyKey = key, stage = ErrorStage.objectStream,
        category = ErrorCategory.malformedData))
    return ok(lookup.value.uintValue == 1)
  if lookup.defaultText == "true": return ok(true)
  if lookup.defaultText == "false": return ok(false)
  err[bool](animationError("animation bool default is invalid",
    propertyKey = key, stage = ErrorStage.objectStream,
    category = ErrorCategory.malformedData))

proc startFrame*(definition: LinearAnimationDefinition): uint32
proc endFrame*(definition: LinearAnimationDefinition): uint32

proc validate*(definition: LinearAnimationDefinition): SplineyStatus =
  if definition.isNil:
    return errStatus(animationError("nil linear animation"))
  if definition.fps == 0:
    return errStatus(animationError("animation fps must be positive",
      definition.objectId, 56))
  if classify(definition.speed) in {fcNan, fcInf, fcNegInf}:
    return errStatus(animationError("animation speed must be finite",
      definition.objectId, 58))
  if definition.enableWorkArea:
    if definition.workStart == MissingObjectId or
        definition.workEnd == MissingObjectId or
        definition.workStart > definition.workEnd or
        definition.workEnd > definition.durationFrames:
      return errStatus(animationError("invalid animation work area",
        definition.objectId, 60))
  if definition.loopMode != LoopMode.oneShot and
      definition.startFrame == definition.endFrame:
    return errStatus(animationError("looping animation range must be positive",
      definition.objectId, 59))
  okStatus()

proc importLinearAnimations*(file: WireFile):
    SplineyResult[seq[LinearAnimationDefinition]] =
  let keyed = importKeyedAnimations(file)
  if not keyed.isOk:
    return err[seq[LinearAnimationDefinition]](keyed.error)
  var keyedIndex = 0
  var animations: seq[LinearAnimationDefinition]
  for index, item in file.objects:
    if item.typeKey != 31:
      continue
    let name = item.stringProperty(55)
    if not name.isOk: return err[seq[LinearAnimationDefinition]](name.error)
    let fps = item.uintProperty(56)
    if not fps.isOk: return err[seq[LinearAnimationDefinition]](fps.error)
    let duration = item.uintProperty(57)
    if not duration.isOk: return err[seq[LinearAnimationDefinition]](duration.error)
    let speed = item.floatProperty(58)
    if not speed.isOk: return err[seq[LinearAnimationDefinition]](speed.error)
    let loopValue = item.uintProperty(59)
    if not loopValue.isOk: return err[seq[LinearAnimationDefinition]](loopValue.error)
    if loopValue.value > LoopMode.pingPong.uint32:
      return err[seq[LinearAnimationDefinition]](animationError(
        "unknown animation loop mode", index.uint32, 59,
        ErrorStage.objectStream, ErrorCategory.unsupportedContent))
    let workStart = item.uintProperty(60, missingSentinel = true)
    if not workStart.isOk: return err[seq[LinearAnimationDefinition]](workStart.error)
    let workEnd = item.uintProperty(61, missingSentinel = true)
    if not workEnd.isOk: return err[seq[LinearAnimationDefinition]](workEnd.error)
    let enableWorkArea = item.boolProperty(62)
    if not enableWorkArea.isOk:
      return err[seq[LinearAnimationDefinition]](enableWorkArea.error)
    let quantize = item.boolProperty(376)
    if not quantize.isOk: return err[seq[LinearAnimationDefinition]](quantize.error)
    if keyedIndex >= keyed.value.len or
        keyed.value[keyedIndex].objectId != index.uint32:
      return err[seq[LinearAnimationDefinition]](animationError(
        "missing keyed animation group", index.uint32))
    let definition = LinearAnimationDefinition(
      objectId: index.uint32,
      name: name.value,
      fps: fps.value,
      durationFrames: duration.value,
      speed: speed.value,
      loopMode: LoopMode(loopValue.value),
      workStart: workStart.value,
      workEnd: workEnd.value,
      enableWorkArea: enableWorkArea.value,
      quantize: quantize.value,
      keyed: keyed.value[keyedIndex])
    let valid = definition.validate()
    if not valid.isOk:
      return err[seq[LinearAnimationDefinition]](valid.error)
    animations.add(definition)
    inc keyedIndex
  ok(animations)

proc startFrame*(definition: LinearAnimationDefinition): uint32 =
  if definition.enableWorkArea: definition.workStart else: 0

proc endFrame*(definition: LinearAnimationDefinition): uint32 =
  if definition.enableWorkArea: definition.workEnd else: definition.durationFrames

proc startSeconds*(definition: LinearAnimationDefinition): float32 =
  definition.startFrame.float32 / definition.fps.float32

proc endSeconds*(definition: LinearAnimationDefinition): float32 =
  definition.endFrame.float32 / definition.fps.float32

proc durationSeconds*(definition: LinearAnimationDefinition): float32 =
  abs(definition.endSeconds - definition.startSeconds)

proc authoredStartTime*(definition: LinearAnimationDefinition): float32 =
  if definition.speed >= 0: definition.startSeconds else: definition.endSeconds

proc authoredEndTime*(definition: LinearAnimationDefinition): float32 =
  if definition.speed >= 0: definition.endSeconds else: definition.startSeconds

proc newLinearAnimationInstance*(definition: LinearAnimationDefinition;
    registry: CorePropertyRegistry; speedMultiplier = 1'f32):
    SplineyResult[LinearAnimationInstance] =
  let valid = definition.validate()
  if not valid.isOk:
    return err[LinearAnimationInstance](valid.error)
  if registry.isNil:
    return err[LinearAnimationInstance](animationError(
      "nil core property registry", definition.objectId))
  if classify(speedMultiplier) in {fcNan, fcInf, fcNegInf}:
    return err[LinearAnimationInstance](animationError(
      "speed multiplier must be finite", definition.objectId,
      stage = ErrorStage.sceneClone))
  let start = if speedMultiplier >= 0: definition.authoredStartTime else:
    definition.authoredEndTime
  ok(LinearAnimationInstance(
    definition: definition,
    registry: registry,
    time: start,
    direction: 1,
    loopOverride: -1))

proc loopMode*(instance: LinearAnimationInstance): LoopMode =
  if instance.loopOverride < 0: instance.definition.loopMode else:
    LoopMode(instance.loopOverride)

proc setLoopMode*(instance: LinearAnimationInstance; value: LoopMode) =
  instance.loopOverride = value.int32

proc clearLoopOverride*(instance: LinearAnimationInstance) =
  instance.loopOverride = -1

proc directedSpeed*(instance: LinearAnimationInstance): float32 =
  instance.direction * instance.definition.speed

proc keepGoing*(instance: LinearAnimationInstance;
    speedMultiplier = 1'f32): bool =
  if instance.loopMode != LoopMode.oneShot:
    return true
  let speed = instance.directedSpeed * speedMultiplier
  (speed > 0 and instance.time < instance.definition.endSeconds) or
    (speed < 0 and instance.time > instance.definition.startSeconds)

proc setDirection*(instance: LinearAnimationInstance; direction: int) =
  instance.direction = if direction > 0: 1 else: -1

proc reset*(instance: LinearAnimationInstance; speedMultiplier = 1'f32) =
  instance.time = if speedMultiplier >= 0:
    instance.definition.authoredStartTime else:
    instance.definition.authoredEndTime
  instance.direction = 1
  instance.totalTime = 0
  instance.lastTotalTime = 0
  instance.spilledTime = 0
  instance.didLoop = false

proc seek*(instance: LinearAnimationInstance; seconds: float32): SplineyStatus =
  if instance.isNil or classify(seconds) in {fcNan, fcInf, fcNegInf}:
    return errStatus(animationError("animation seek time must be finite",
      stage = ErrorStage.frameAdvance))
  if instance.time == seconds:
    return okStatus()
  let difference = instance.totalTime - instance.lastTotalTime
  instance.time = seconds
  instance.totalTime = seconds - instance.definition.startSeconds
  instance.lastTotalTime = instance.totalTime - difference
  instance.direction = 1
  okStatus()

proc advance*(instance: LinearAnimationInstance; elapsedSeconds: float32):
    SplineyResult[bool] =
  if instance.isNil or classify(elapsedSeconds) in {fcNan, fcInf, fcNegInf}:
    return err[bool](animationError("animation delta must be finite",
      stage = ErrorStage.frameAdvance))
  let definition = instance.definition
  var deltaSeconds = elapsedSeconds * definition.speed * instance.direction
  if classify(deltaSeconds) in {fcNan, fcInf, fcNegInf}:
    return err[bool](animationError("animation delta overflow",
      definition.objectId, stage = ErrorStage.frameAdvance))
  instance.spilledTime = 0
  if deltaSeconds == 0:
    instance.didLoop = false
    return ok(false)

  instance.lastTotalTime = instance.totalTime
  instance.totalTime += abs(deltaSeconds)
  let killSpilledTime = not instance.keepGoing(elapsedSeconds)
  instance.time += deltaSeconds

  let fps = definition.fps.float32
  var frames = instance.time * fps
  let start = definition.startFrame.float32
  let finish = definition.endFrame.float32
  let frameRange = finish - start
  var didLoop = false
  var direction = if deltaSeconds < 0: -1 else: 1

  case instance.loopMode
  of LoopMode.oneShot:
    if direction == 1 and frames > finish:
      let deltaFrames = deltaSeconds * fps
      instance.spilledTime = (frames - finish) / deltaFrames * elapsedSeconds
      frames = finish
      instance.time = frames / fps
      didLoop = true
    elif direction == -1 and frames < start:
      let deltaFrames = abs(deltaSeconds * fps)
      instance.spilledTime = (start - frames) / deltaFrames * elapsedSeconds
      frames = start
      instance.time = frames / fps
      didLoop = true
  of LoopMode.loop:
    if direction == 1 and frames >= finish:
      let deltaFrames = deltaSeconds * fps
      let remainder = floorMod(frames - start, frameRange)
      instance.spilledTime = remainder / deltaFrames * elapsedSeconds
      frames = start + remainder
      instance.time = frames / fps
      didLoop = true
    elif direction == -1 and frames <= start:
      let deltaFrames = deltaSeconds * fps
      let remainder = abs(floorMod(start - frames, frameRange))
      instance.spilledTime = abs(remainder / deltaFrames) * elapsedSeconds
      frames = finish - remainder
      instance.time = frames / fps
      didLoop = true
  of LoopMode.pingPong:
    while true:
      if direction == 1 and frames >= finish:
        instance.spilledTime = (frames - finish) / fps
        frames = finish + (finish - frames)
      elif direction == -1 and frames < start:
        instance.spilledTime = (start - frames) / fps
        frames = start + (start - frames)
      else:
        break
      instance.time = frames / fps
      instance.direction *= -1
      direction *= -1
      didLoop = true

  if killSpilledTime:
    instance.spilledTime = 0
  instance.didLoop = didLoop
  ok(instance.keepGoing(elapsedSeconds))

proc apply*(instance: LinearAnimationInstance; mix = 1'f32): SplineyStatus =
  if instance.isNil:
    return errStatus(animationError("nil linear animation instance",
      stage = ErrorStage.frameAdvance))
  var applicationTime = instance.time
  if instance.definition.quantize:
    let fps = instance.definition.fps.float32
    applicationTime = floor(applicationTime * fps) / fps
  instance.definition.keyed.apply(instance.registry, applicationTime,
    instance.definition.fps.float32, mix)

proc advanceAndApply*(instance: LinearAnimationInstance;
    elapsedSeconds: float32; mix = 1'f32): SplineyResult[bool] =
  let advanced = instance.advance(elapsedSeconds)
  if not advanced.isOk:
    return advanced
  let applied = instance.apply(mix)
  if not applied.isOk:
    return err[bool](applied.error)
  advanced
