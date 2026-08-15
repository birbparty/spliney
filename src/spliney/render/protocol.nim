## Renderer-neutral mirror of Rive's Renderer and Factory seams.
##
## Owning handles are ORC-managed references. Renderer arguments are borrowed
## for the duration of each call; native/GPU cleanup remains explicit in the
## concrete backend.

import spliney/errors
import spliney/math/geometry

type
  ColorInt* = uint32

  FillRule* {.pure.} = enum
    nonZero = 0
    evenOdd = 1
    clockwise = 2

  PathVerb* {.pure.} = enum
    move = 0
    line = 1
    quad = 2
    cubic = 4
    close = 5

  BlendMode* {.pure.} = enum
    srcOver = 3
    screen = 14
    overlay = 15
    darken = 16
    lighten = 17
    colorDodge = 18
    colorBurn = 19
    hardLight = 20
    softLight = 21
    difference = 22
    exclusion = 23
    multiply = 24
    hue = 25
    saturation = 26
    color = 27
    luminosity = 28

  ImageFilter* {.pure.} = enum
    bilinear = 0
    nearest = 1

  ImageWrap* {.pure.} = enum
    clamp = 0
    repeat = 1
    mirror = 2

  ImageSampler* = object
    wrapX*: ImageWrap
    wrapY*: ImageWrap
    filter*: ImageFilter

  StrokeCap* {.pure.} = enum
    butt = 0
    round = 1
    square = 2

  StrokeJoin* {.pure.} = enum
    miter = 0
    round = 1
    bevel = 2

  RenderPaintStyle* {.pure.} = enum
    stroke = 0
    fill = 1

  RenderBufferType* {.pure.} = enum
    index = 0
    vertex = 1

  RenderBufferFlag* {.pure.} = enum
    mappedOnceAtInitialization

  RenderBufferFlags* = set[RenderBufferFlag]

  RawPath* = object
    verbs*: seq[PathVerb]
    points*: seq[Vec2D]

  PreparedImage* = ref object of RootObj
    ## Backend-owned decoded/uploaded image handle.

  ResourceFactory* = ref object of RootObj
    ## Public resource-acquisition base. Factory extends this with the complete
    ## Rive rendering-resource surface.

  RenderSink* = ref object of RootObj
    ## Public draw-destination base. Renderer extends this with eight commands.

  RenderShader* = ref object of RootObj

  RenderImage* = ref object of PreparedImage
    imageWidth: int
    imageHeight: int
    imageUvTransform: Mat2D

  RenderBuffer* = ref object of RootObj
    bufferType*: RenderBufferType
    flags*: RenderBufferFlags
    sizeInBytes*: int
    mapped: bool
    dirty: bool

  RenderPaint* = ref object of RootObj

  RenderPath* = ref object of RootObj
    fillRule*: FillRule

  Factory* = ref object of ResourceFactory

  Renderer* = ref object of RenderSink

const LinearClampSampler* = ImageSampler(
  wrapX: ImageWrap.clamp,
  wrapY: ImageWrap.clamp,
  filter: ImageFilter.bilinear)

proc asKey*(sampler: ImageSampler): uint8 =
  uint8(ord(sampler.wrapX) + ord(sampler.wrapY) * 3 +
    ord(sampler.filter) * 9)

proc samplerFromKey*(key: uint8): ImageSampler =
  ImageSampler(
    wrapX: ImageWrap(int(key) mod 3),
    wrapY: ImageWrap((int(key) div 3) mod 3),
    filter: ImageFilter(int(key) div 9))

proc moveTo*(path: var RawPath; point: Vec2D) =
  path.verbs.add(PathVerb.move)
  path.points.add(point)

proc lineTo*(path: var RawPath; point: Vec2D) =
  path.verbs.add(PathVerb.line)
  path.points.add(point)

proc quadTo*(path: var RawPath; control, point: Vec2D) =
  path.verbs.add(PathVerb.quad)
  path.points.add(control)
  path.points.add(point)

proc cubicTo*(path: var RawPath; control1, control2, point: Vec2D) =
  path.verbs.add(PathVerb.cubic)
  path.points.add(control1)
  path.points.add(control2)
  path.points.add(point)

proc close*(path: var RawPath) = path.verbs.add(PathVerb.close)

proc configureImage*(image: RenderImage; width, height: int;
    uvTransform = IdentityMat2D) =
  image.imageWidth = width
  image.imageHeight = height
  image.imageUvTransform = uvTransform

proc width*(image: RenderImage): int = image.imageWidth
proc height*(image: RenderImage): int = image.imageHeight
proc uvTransform*(image: RenderImage): Mat2D = image.imageUvTransform

method onMap*(buffer: RenderBuffer): pointer {.base.} =
  discard buffer
  nil

method onUnmap*(buffer: RenderBuffer) {.base.} = discard buffer

proc map*(buffer: RenderBuffer): pointer =
  doAssert not buffer.isNil and not buffer.mapped,
    "RenderBuffer must be non-nil and unmapped"
  buffer.mapped = true
  buffer.dirty = true
  buffer.onMap()

proc unmap*(buffer: RenderBuffer) =
  doAssert not buffer.isNil and buffer.mapped,
    "RenderBuffer must be mapped before unmap"
  buffer.onUnmap()
  buffer.mapped = false

proc checkAndResetDirty*(buffer: RenderBuffer): bool =
  doAssert not buffer.isNil and not buffer.mapped,
    "RenderBuffer dirty state cannot be read while mapped"
  result = buffer.dirty
  buffer.dirty = false

method style*(paint: RenderPaint; value: RenderPaintStyle) {.base.} =
  discard paint
  discard value
method color*(paint: RenderPaint; value: ColorInt) {.base.} =
  discard paint
  discard value
method thickness*(paint: RenderPaint; value: float32) {.base.} =
  discard paint
  discard value
method join*(paint: RenderPaint; value: StrokeJoin) {.base.} =
  discard paint
  discard value
method cap*(paint: RenderPaint; value: StrokeCap) {.base.} =
  discard paint
  discard value
method feather*(paint: RenderPaint; value: float32) {.base.} =
  discard paint
  discard value
method blendMode*(paint: RenderPaint; value: BlendMode) {.base.} =
  discard paint
  discard value
method shader*(paint: RenderPaint; value: RenderShader) {.base.} =
  discard paint
  discard value
method invalidateStroke*(paint: RenderPaint) {.base.} = discard paint

method addRenderPath*(path: RenderPath; other: RenderPath;
    transform: Mat2D) {.base.} =
  discard path
  discard other
  discard transform
method addRenderPathBackwards*(path: RenderPath; other: RenderPath;
    transform: Mat2D) {.base.} =
  discard path
  discard other
  discard transform
method addRawPath*(path: RenderPath; raw: RawPath) {.base.} =
  discard path
  discard raw

# The eight virtual renderer operations, kept in the same order as Rive.
method save*(renderer: Renderer) {.base.} = discard renderer
method restore*(renderer: Renderer) {.base.} = discard renderer
method transform*(renderer: Renderer; value: Mat2D) {.base.} =
  discard renderer
  discard value
method drawPath*(renderer: Renderer; path: RenderPath;
    paint: RenderPaint) {.base.} =
  discard renderer
  discard path
  discard paint
method clipPath*(renderer: Renderer; path: RenderPath) {.base.} =
  discard renderer
  discard path
method drawImage*(renderer: Renderer; image: RenderImage;
    sampler: ImageSampler; blendMode: BlendMode; opacity: float32) {.base.} =
  discard renderer
  discard image
  discard sampler
  discard blendMode
  discard opacity
method drawImageMesh*(renderer: Renderer; image: RenderImage;
    sampler: ImageSampler; vertices, uvCoords, indices: RenderBuffer;
    vertexCount, indexCount: uint32; blendMode: BlendMode;
    opacity: float32) {.base.} =
  discard renderer
  discard image
  discard sampler
  discard vertices
  discard uvCoords
  discard indices
  discard vertexCount
  discard indexCount
  discard blendMode
  discard opacity
method modulateOpacity*(renderer: Renderer; opacity: float32) {.base.} =
  discard renderer
  discard opacity

proc translate*(renderer: Renderer; x, y: float32) =
  renderer.transform(translationMat2D(x, y))
proc scale*(renderer: Renderer; x, y: float32) =
  renderer.transform(scaleMat2D(x, y))
proc rotate*(renderer: Renderer; radians: float32) =
  renderer.transform(rotationMat2D(radians))

method makeRenderBuffer*(factory: Factory; bufferType: RenderBufferType;
    flags: RenderBufferFlags; sizeInBytes: int): RenderBuffer {.base.} =
  discard factory
  RenderBuffer(bufferType: bufferType, flags: flags, sizeInBytes: sizeInBytes)
method makeLinearGradient*(factory: Factory; startPoint, endPoint: Vec2D;
    colors: openArray[ColorInt]; stops: openArray[float32]): RenderShader {.base.} =
  discard factory
  discard startPoint
  discard endPoint
  discard colors
  discard stops
  nil
method makeRadialGradient*(factory: Factory; center: Vec2D; radius: float32;
    colors: openArray[ColorInt]; stops: openArray[float32]): RenderShader {.base.} =
  discard factory
  discard center
  discard radius
  discard colors
  discard stops
  nil
method makeRenderPath*(factory: Factory; raw: var RawPath;
    fillRule: FillRule): RenderPath {.base.} =
  discard factory
  RenderPath(fillRule: fillRule)
method makeEmptyRenderPath*(factory: Factory): RenderPath {.base.} =
  discard factory
  RenderPath(fillRule: FillRule.nonZero)
method makeRenderPaint*(factory: Factory): RenderPaint {.base.} =
  discard factory
  RenderPaint()
method decodeImage*(factory: Factory;
    compressedBytes: openArray[byte]): RenderImage {.base.} =
  discard factory
  discard compressedBytes
  nil

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
