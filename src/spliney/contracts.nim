## Public, renderer-neutral consumer contract for Spliney.
##
## The concrete importer/runtime is implemented behind these opaque handles.
## Gate 0 freezes their ownership and error semantics before those bodies are
## filled in. Importing this module never imports a graphics package.

type
  ErrorCategory* {.pure.} = enum
    consumerIo
    malformedData
    incompatibleFormat
    unsupportedContent
    resolution
    scene
    assetDecode
    backend
    render
    lifecycle

  ErrorStage* {.pure.} = enum
    fileRead
    header
    tableOfContents
    objectStream
    referenceResolution
    defaultArtboardSelection
    sceneClone
    initialSettle
    frameAdvance
    imageDecode
    contextInitialization
    resourceAcquisition
    drawSubmission
    captureReadback
    cleanup

  ErrorContext* = object
    label*: string
    objectTypeKey*: int32
    propertyKey*: int32
    assetId*: int64
    assetName*: string
    animationIndex*: int32
    animationName*: string
    hasByteOffset*: bool
    byteOffset*: uint64

  SplineyError* = object
    category*: ErrorCategory
    stage*: ErrorStage
    message*: string
    context*: ErrorContext

  SplineyResult*[T] = object
    case isOk*: bool
    of true:
      value*: T
    of false:
      error*: SplineyError

  SplineyStatus* = object
    case isOk*: bool
    of true:
      discard
    of false:
      error*: SplineyError

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

  PreparedResources* = ref object
    ## Shared decoded/backend resources prepared while a context is valid.
    closed: bool

  PlayableScene* = ref object
    ## Independent mutable artboard, dependency, and animation state.
    closed: bool

  ResourceFactory* = ref object of RootObj
    ## Backend-defined resource acquisition seam. Concrete methods are frozen
    ## by ADR 0003: adapters receive stable asset identity, immutable compressed
    ## bytes owned by the file, and expected dimensions; backend types stay out.

  RenderSink* = ref object of RootObj
    ## Backend-neutral draw destination. Concrete command methods live in the
    ## render protocol module and do not expose Naylib/Raylib through core.

proc ok*[T](value: sink T): SplineyResult[T] =
  SplineyResult[T](isOk: true, value: value)

proc err*[T](error: sink SplineyError): SplineyResult[T] =
  SplineyResult[T](isOk: false, error: error)

proc okStatus*(): SplineyStatus = SplineyStatus(isOk: true)

proc errStatus*(error: sink SplineyError): SplineyStatus =
  SplineyStatus(isOk: false, error: error)

proc contractPending[T](stage: ErrorStage; label = ""): SplineyResult[T] =
  err[T](SplineyError(
    category: ErrorCategory.unsupportedContent,
    stage: stage,
    message: "runtime implementation for the frozen public contract is pending",
    context: ErrorContext(label: label, objectTypeKey: -1,
      propertyKey: -1, assetId: -1, animationIndex: -1)))

proc importRive*(bytes: openArray[byte]; label = "<memory>"):
    SplineyResult[ImportedRiveFile] =
  ## Imports caller bytes into an immutable owned file definition. A successful
  ## result never borrows `bytes`; the caller may release them immediately.
  discard bytes
  contractPending[ImportedRiveFile](ErrorStage.objectStream, label)

proc loadRiveFile*(path: string; label = ""): SplineyResult[ImportedRiveFile] =
  ## File-reading convenience with stable path/label error context.
  contractPending[ImportedRiveFile](ErrorStage.fileRead,
    if label.len > 0: label else: path)

proc defaultArtboard*(file: ImportedRiveFile): SplineyResult[ArtboardInfo] =
  ## Returns immutable metadata for the declared default artboard.
  discard file
  contractPending[ArtboardInfo](ErrorStage.defaultArtboardSelection)

proc prepareResources*(file: ImportedRiveFile; factory: ResourceFactory):
    SplineyResult[PreparedResources] =
  ## Decodes/uploads shared resources after a backend context exists.
  discard file
  discard factory
  contractPending[PreparedResources](ErrorStage.resourceAcquisition)

proc newScene*(file: ImportedRiveFile; artboardIndex, animationIndex: int):
    SplineyResult[PlayableScene] =
  ## Clones fresh mutable state while sharing only immutable file data.
  discard file
  discard artboardIndex
  discard animationIndex
  contractPending[PlayableScene](ErrorStage.sceneClone)

proc initialSettle*(scene: PlayableScene): SplineyStatus =
  ## Applies the authored start pose and settles dependencies without weakening
  ## the positive-delta frame contract.
  discard scene
  errStatus(contractPending[bool](ErrorStage.initialSettle).error)

proc advanceAndApply*(scene: PlayableScene; dt: float32): SplineyStatus =
  ## Advances continuous time, applies properties, and settles dependencies.
  ## Runtime validation requires finite `0 < dt <= 0.1`.
  discard scene
  discard dt
  errStatus(contractPending[bool](ErrorStage.frameAdvance).error)

proc replaceAnimation*(scene: var PlayableScene; animationIndex: int):
    SplineyStatus =
  ## Transactionally constructs and settles replacement state. Failure leaves
  ## `scene` behaviorally unchanged; success disposes the old state after swap.
  discard scene
  discard animationIndex
  errStatus(contractPending[bool](ErrorStage.sceneClone).error)

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
  okStatus()

proc close*(resources: PreparedResources): SplineyStatus =
  ## Idempotently releases decoded/native/GPU resources. Must run before the
  ## backend context closes. Safe on nil.
  if resources.isNil or resources.closed: return okStatus()
  resources.closed = true
  okStatus()

proc close*(file: ImportedRiveFile): SplineyStatus =
  ## Idempotently releases immutable definitions after scenes/resources close.
  ## Safe on nil.
  if file.isNil or file.closed: return okStatus()
  file.closed = true
  okStatus()
