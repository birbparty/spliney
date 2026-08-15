## Renderer-neutral structured errors shared by the public facade and core.

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

proc ok*[T](value: sink T): SplineyResult[T] =
  SplineyResult[T](isOk: true, value: value)

proc err*[T](error: sink SplineyError): SplineyResult[T] =
  SplineyResult[T](isOk: false, error: error)

proc okStatus*(): SplineyStatus = SplineyStatus(isOk: true)

proc errStatus*(error: sink SplineyError): SplineyStatus =
  SplineyStatus(isOk: false, error: error)
