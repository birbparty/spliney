## Public, renderer-neutral consumer contract for Spliney.
##
## The concrete importer/runtime is implemented behind these opaque handles.
## Gate 0 freezes their ownership and error semantics before those bodies are
## filled in. Importing this module never imports a graphics package.

import spliney/animation/engine/linear
import spliney/errors
import spliney/io/loader
import spliney/scene/artboard

export errors

type
  Vec2* = object
    x*: float32
    y*: float32

  Rect* = object
    minX*: float32
    minY*: float32
    maxX*: float32
    maxY*: float32

  AnimationInfo* = object
    index*: int
    name*: string
    fps*: float32
    durationFrames*: uint32
    durationSeconds*: float32
    speed*: float32
    direction*: int8
    loopValue*: uint32
    workAreaEnabled*: bool
    workStartFrame*: uint32
    workEndFrame*: uint32

  ArtboardInfo* = object
    index*: int
    name*: string
    bounds*: Rect
    animations*: seq[AnimationInfo]

  ImportedRiveFile* = ref object
    ## Immutable resolved definitions plus owned compressed embedded bytes.
    label: string
    closed: bool
    wire: WireFile
    artboards: seq[ArtboardDefinition]
    sceneCount: int
    resourceCount: int

  PreparedImage* = ref object of RootObj
    ## Backend-owned decoded/uploaded image handle.

  PreparedResources* = ref object
    ## Shared decoded/backend resources prepared while a context is valid.
    closed: bool
    owner: ImportedRiveFile
    factory: ResourceFactory
    images: seq[PreparedImage]

  PlayableScene* = ref object
    ## Independent mutable artboard, dependency, and animation state.
    closed: bool
    owner: ImportedRiveFile
    runtime: ArtboardInstance

  ResourceFactory* = ref object of RootObj
    ## Backend-defined resource acquisition seam. Concrete methods are frozen
    ## by ADR 0003: adapters receive stable asset identity, immutable compressed
    ## bytes owned by the file, and expected dimensions; backend types stay out.

  RenderSink* = ref object of RootObj
    ## Backend-neutral draw destination. Concrete command methods live in the
    ## render protocol module and do not expose Naylib/Raylib through core.

method prepareEmbeddedPng*(factory: ResourceFactory; assetIndex: uint32;
    name: string; compressedBytes: openArray[byte]; expectedWidth,
    expectedHeight: uint32): SplineyResult[PreparedImage] {.base.} =
  discard factory
  discard name
  discard compressedBytes
  discard expectedWidth
  discard expectedHeight
  err[PreparedImage](SplineyError(
    category: ErrorCategory.unsupportedContent,
    stage: ErrorStage.resourceAcquisition,
    message: "resource factory does not prepare embedded PNG images",
    context: ErrorContext(objectTypeKey: 105, propertyKey: 212,
      assetId: assetIndex.int64, animationIndex: -1)))

method releasePreparedImage*(factory: ResourceFactory;
    image: PreparedImage): SplineyStatus {.base.} =
  discard factory
  discard image
  okStatus()

proc contractPending[T](stage: ErrorStage; label = ""): SplineyResult[T] =
  err[T](SplineyError(
    category: ErrorCategory.unsupportedContent,
    stage: stage,
    message: "runtime implementation for the frozen public contract is pending",
    context: ErrorContext(label: label, objectTypeKey: -1,
      propertyKey: -1, assetId: -1, animationIndex: -1)))

proc lifecycleError[T](message: string; stage: ErrorStage;
    label = ""): SplineyResult[T] =
  err[T](SplineyError(
    category: ErrorCategory.lifecycle,
    stage: stage,
    message: message,
    context: ErrorContext(label: label, objectTypeKey: -1,
      propertyKey: -1, assetId: -1, animationIndex: -1)))

proc importRive*(bytes: openArray[byte]; label = "<memory>"):
    SplineyResult[ImportedRiveFile] =
  ## Imports caller bytes into an immutable owned file definition. A successful
  ## result never borrows `bytes`; the caller may release them immediately.
  let loaded = loadRiveWire(bytes, label)
  if not loaded.isOk:
    return err[ImportedRiveFile](loaded.error)
  let artboards = importArtboards(loaded.value)
  if not artboards.isOk:
    return err[ImportedRiveFile](artboards.error)
  ok(ImportedRiveFile(
    label: label,
    wire: loaded.value,
    artboards: artboards.value))

proc loadRiveFile*(path: string; label = ""): SplineyResult[ImportedRiveFile] =
  ## File-reading convenience with stable path/label error context.
  let effectiveLabel = if label.len > 0: label else: path
  var raw: string
  try:
    raw = readFile(path)
  except CatchableError:
    return err[ImportedRiveFile](SplineyError(
      category: ErrorCategory.consumerIo,
      stage: ErrorStage.fileRead,
      message: "unable to read Rive file",
      context: ErrorContext(label: effectiveLabel, objectTypeKey: -1,
        propertyKey: -1, assetId: -1, animationIndex: -1)))
  if raw.len == 0:
    importRive([], effectiveLabel)
  else:
    importRive(raw.toOpenArrayByte(0, raw.high), effectiveLabel)

proc defaultArtboard*(file: ImportedRiveFile): SplineyResult[ArtboardInfo] =
  ## Returns immutable metadata for the declared default artboard.
  if file.isNil or file.closed:
    return lifecycleError[ArtboardInfo]("imported Rive file is closed",
      ErrorStage.defaultArtboardSelection)
  if file.artboards.len == 0:
    return err[ArtboardInfo](SplineyError(
      category: ErrorCategory.resolution,
      stage: ErrorStage.defaultArtboardSelection,
      message: "Rive file contains no default artboard",
      context: ErrorContext(label: file.label, objectTypeKey: -1,
        propertyKey: -1, assetId: -1, animationIndex: -1)))
  let definition = file.artboards[0]
  var animations: seq[AnimationInfo]
  for index, animation in definition.animations:
    animations.add(AnimationInfo(
      index: index,
      name: animation.name,
      fps: animation.fps.float32,
      durationFrames: animation.durationFrames,
      durationSeconds: animation.durationSeconds,
      speed: animation.speed,
      direction: (if animation.speed < 0: -1 else: 1),
      loopValue: animation.loopMode.uint32,
      workAreaEnabled: animation.enableWorkArea,
      workStartFrame: animation.startFrame,
      workEndFrame: animation.endFrame))
  ok(ArtboardInfo(
    index: 0,
    name: definition.name,
    bounds: Rect(minX: 0, minY: 0,
      maxX: definition.width, maxY: definition.height),
    animations: animations))

proc prepareResources*(file: ImportedRiveFile; factory: ResourceFactory):
    SplineyResult[PreparedResources] =
  ## Decodes/uploads shared resources after a backend context exists.
  if file.isNil or file.closed:
    return lifecycleError[PreparedResources]("imported Rive file is closed",
      ErrorStage.resourceAcquisition)
  if factory.isNil:
    return lifecycleError[PreparedResources]("resource factory is nil",
      ErrorStage.resourceAcquisition, file.label)
  var images: seq[PreparedImage]
  let embedded = file.artboards[0].imageAssets
  for asset in embedded:
    let prepared = if asset.compressedBytes.len == 0:
      factory.prepareEmbeddedPng(asset.index, asset.name, [],
        asset.width.uint32, asset.height.uint32)
    else:
      factory.prepareEmbeddedPng(asset.index, asset.name,
        asset.compressedBytes.toOpenArrayByte(0, asset.compressedBytes.high),
        asset.width.uint32, asset.height.uint32)
    if not prepared.isOk:
      for index in countdown(images.high, 0):
        discard factory.releasePreparedImage(images[index])
      return err[PreparedResources](prepared.error)
    if prepared.value.isNil:
      for index in countdown(images.high, 0):
        discard factory.releasePreparedImage(images[index])
      return err[PreparedResources](SplineyError(
        category: ErrorCategory.backend,
        stage: ErrorStage.resourceAcquisition,
        message: "resource factory returned a nil prepared image",
        context: ErrorContext(label: file.label, objectTypeKey: 105,
          propertyKey: 212, assetId: asset.index.int64, animationIndex: -1)))
    images.add(prepared.value)
  inc file.resourceCount
  ok(PreparedResources(owner: file, factory: factory, images: move(images)))

proc newScene*(file: ImportedRiveFile; artboardIndex, animationIndex: int):
    SplineyResult[PlayableScene] =
  ## Clones fresh mutable state while sharing only immutable file data.
  if file.isNil or file.closed:
    return lifecycleError[PlayableScene]("imported Rive file is closed",
      ErrorStage.sceneClone)
  if artboardIndex < 0 or artboardIndex >= file.artboards.len:
    return err[PlayableScene](SplineyError(
      category: ErrorCategory.scene,
      stage: ErrorStage.sceneClone,
      message: "artboard index out of range",
      context: ErrorContext(label: file.label, objectTypeKey: -1,
        propertyKey: -1, assetId: -1, animationIndex: animationIndex.int32)))
  let cloned = file.artboards[artboardIndex].cloneArtboard(animationIndex)
  if not cloned.isOk:
    return err[PlayableScene](cloned.error)
  inc file.sceneCount
  ok(PlayableScene(owner: file, runtime: cloned.value))

proc initialSettle*(scene: PlayableScene): SplineyStatus =
  ## Applies the authored start pose and settles dependencies without weakening
  ## the positive-delta frame contract.
  if scene.isNil or scene.closed:
    return errStatus(lifecycleError[bool]("playable scene is closed",
      ErrorStage.initialSettle).error)
  scene.runtime.initialSettle()

proc advanceAndApply*(scene: PlayableScene; dt: float32): SplineyStatus =
  ## Advances continuous time, applies properties, and settles dependencies.
  ## Runtime validation requires finite `0 < dt <= 0.1`.
  if scene.isNil or scene.closed:
    return errStatus(lifecycleError[bool]("playable scene is closed",
      ErrorStage.frameAdvance).error)
  scene.runtime.advanceAndApply(dt)

proc replaceAnimation*(scene: var PlayableScene; animationIndex: int):
    SplineyStatus =
  ## Transactionally constructs and settles replacement state. Failure leaves
  ## `scene` behaviorally unchanged; success disposes the old state after swap.
  if scene.isNil or scene.closed:
    return errStatus(lifecycleError[bool]("playable scene is closed",
      ErrorStage.sceneClone).error)
  scene.runtime.replaceAnimation(animationIndex)

proc draw*(scene: PlayableScene; resources: PreparedResources;
    renderer: RenderSink; destination: Rect; screenTranslation = Vec2()):
    SplineyStatus =
  ## Emits backend-neutral commands using contain-fit followed by translation
  ## expressed in destination/screen pixels.
  discard scene
  discard resources
  discard renderer
  discard destination
  discard screenTranslation
  errStatus(contractPending[bool](ErrorStage.drawSubmission).error)

proc close*(scene: PlayableScene): SplineyStatus =
  ## Idempotently releases mutable scene state. Safe on nil.
  if scene.isNil or scene.closed: return okStatus()
  scene.closed = true
  scene.runtime = nil
  if not scene.owner.isNil and scene.owner.sceneCount > 0:
    dec scene.owner.sceneCount
  scene.owner = nil
  okStatus()

proc close*(resources: PreparedResources): SplineyStatus =
  ## Idempotently releases decoded/native/GPU resources. Must run before the
  ## backend context closes. Safe on nil.
  if resources.isNil or resources.closed: return okStatus()
  resources.closed = true
  var firstFailure: SplineyError
  var failed = false
  for index in countdown(resources.images.high, 0):
    let released = resources.factory.releasePreparedImage(resources.images[index])
    if not released.isOk and not failed:
      firstFailure = released.error
      failed = true
  resources.images.setLen(0)
  resources.factory = nil
  if not resources.owner.isNil and resources.owner.resourceCount > 0:
    dec resources.owner.resourceCount
  resources.owner = nil
  if failed: errStatus(firstFailure) else: okStatus()

proc close*(file: ImportedRiveFile): SplineyStatus =
  ## Idempotently releases immutable definitions after scenes/resources close.
  ## Safe on nil.
  if file.isNil or file.closed: return okStatus()
  if file.sceneCount != 0 or file.resourceCount != 0:
    return errStatus(lifecycleError[bool](
      "cannot close imported Rive file with live scenes or resources",
      ErrorStage.cleanup, file.label).error)
  file.closed = true
  file.artboards.setLen(0)
  file.wire = nil
  okStatus()
