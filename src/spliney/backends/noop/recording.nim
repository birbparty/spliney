## Dependency-free recording Renderer/Factory backend.
##
## It performs no display work. Every renderer operation is captured in order,
## including the effective matrix/opacity and immutable snapshots of mesh
## buffers, so tests can compare or hash a canonical command stream.

import spliney/errors
import spliney/math/geometry
import spliney/render/protocol

type
  RecordedCommandKind* {.pure.} = enum
    save
    restore
    transform
    drawPath
    clipPath
    drawImage
    drawImageMesh
    modulateOpacity

  RecordedCommand* = object
    kind*: RecordedCommandKind
    transform*: Mat2D
    opacity*: float32
    resourceId*: uint32
    samplerKey*: uint8
    blendModeValue*: uint8
    fillRule*: FillRule
    paintStyle*: RenderPaintStyle
    color*: ColorInt
    pathVerbs*: seq[PathVerb]
    pathPoints*: seq[float32]
    vertices*: seq[float32]
    uvCoords*: seq[float32]
    indices*: seq[uint16]

  RendererState = object
    transform: Mat2D
    opacity: float32

  NoOpRenderer* = ref object of Renderer
    commands*: seq[RecordedCommand]
    stack: seq[RendererState]
    state: RendererState
    invariantErrors*: seq[string]

  NoOpRenderBuffer* = ref object of RenderBuffer
    bytes*: seq[byte]

  NoOpRenderShader* = ref object of RenderShader
    resourceId*: uint32

  NoOpRenderImage* = ref object of RenderImage
    assetIndex*: uint32
    released*: bool

  NoOpRenderPaint* = ref object of RenderPaint
    resourceId*: uint32
    paintStyle*: RenderPaintStyle
    paintColor*: ColorInt
    paintThickness*: float32
    paintJoin*: StrokeJoin
    paintCap*: StrokeCap
    paintFeather*: float32
    paintBlendMode*: BlendMode
    paintShader*: RenderShader
    strokeInvalidations*: int

  NoOpRenderPath* = ref object of RenderPath
    resourceId*: uint32
    raw*: RawPath

  NoOpFactory* = ref object of Factory
    nextResourceId: uint32
    preparedCount*: int
    releasedCount*: int

proc newNoOpRenderer*(): NoOpRenderer =
  NoOpRenderer(state: RendererState(
    transform: IdentityMat2D,
    opacity: 1'f32))

proc newNoOpFactory*(): NoOpFactory = NoOpFactory(nextResourceId: 1)

proc allocateId(factory: NoOpFactory): uint32 =
  result = factory.nextResourceId
  inc factory.nextResourceId

method onMap*(buffer: NoOpRenderBuffer): pointer =
  if buffer.bytes.len == 0: nil else: addr buffer.bytes[0]

method onUnmap*(buffer: NoOpRenderBuffer) = discard buffer

method style*(paint: NoOpRenderPaint; value: RenderPaintStyle) =
  paint.paintStyle = value
method color*(paint: NoOpRenderPaint; value: ColorInt) =
  paint.paintColor = value
method thickness*(paint: NoOpRenderPaint; value: float32) =
  paint.paintThickness = value
method join*(paint: NoOpRenderPaint; value: StrokeJoin) =
  paint.paintJoin = value
method cap*(paint: NoOpRenderPaint; value: StrokeCap) =
  paint.paintCap = value
method feather*(paint: NoOpRenderPaint; value: float32) =
  paint.paintFeather = value
method blendMode*(paint: NoOpRenderPaint; value: BlendMode) =
  paint.paintBlendMode = value
method shader*(paint: NoOpRenderPaint; value: RenderShader) =
  paint.paintShader = value
method invalidateStroke*(paint: NoOpRenderPaint) =
  inc paint.strokeInvalidations

proc appendRaw(destination: var RawPath; source: RawPath;
    transform: Mat2D; backwards: bool) =
  if backwards:
    for index in countdown(source.verbs.high, 0):
      destination.verbs.add(source.verbs[index])
    for index in countdown(source.points.high, 0):
      destination.points.add(transform * source.points[index])
  else:
    destination.verbs.add(source.verbs)
    for point in source.points:
      destination.points.add(transform * point)

method addRenderPath*(path: NoOpRenderPath; other: RenderPath;
    transform: Mat2D) =
  if other of NoOpRenderPath:
    path.raw.appendRaw(NoOpRenderPath(other).raw, transform, false)

method addRenderPathBackwards*(path: NoOpRenderPath; other: RenderPath;
    transform: Mat2D) =
  if other of NoOpRenderPath:
    path.raw.appendRaw(NoOpRenderPath(other).raw, transform, true)

method addRawPath*(path: NoOpRenderPath; raw: RawPath) =
  path.raw.verbs.add(raw.verbs)
  path.raw.points.add(raw.points)

method makeRenderBuffer*(factory: NoOpFactory;
    bufferType: RenderBufferType; flags: RenderBufferFlags;
    sizeInBytes: int): RenderBuffer =
  NoOpRenderBuffer(
    bufferType: bufferType,
    flags: flags,
    sizeInBytes: sizeInBytes,
    bytes: newSeq[byte](sizeInBytes))

method makeLinearGradient*(factory: NoOpFactory;
    startPoint, endPoint: Vec2D; colors: openArray[ColorInt];
    stops: openArray[float32]): RenderShader =
  discard startPoint
  discard endPoint
  discard colors
  discard stops
  NoOpRenderShader(resourceId: factory.allocateId())

method makeRadialGradient*(factory: NoOpFactory; center: Vec2D;
    radius: float32; colors: openArray[ColorInt];
    stops: openArray[float32]): RenderShader =
  discard center
  discard radius
  discard colors
  discard stops
  NoOpRenderShader(resourceId: factory.allocateId())

method makeRenderPath*(factory: NoOpFactory; raw: var RawPath;
    fillRule: FillRule): RenderPath =
  result = NoOpRenderPath(
    resourceId: factory.allocateId(),
    fillRule: fillRule,
    raw: move(raw))

method makeEmptyRenderPath*(factory: NoOpFactory): RenderPath =
  NoOpRenderPath(resourceId: factory.allocateId(),
    fillRule: FillRule.nonZero)

method makeRenderPaint*(factory: NoOpFactory): RenderPaint =
  NoOpRenderPaint(
    resourceId: factory.allocateId(),
    paintStyle: RenderPaintStyle.fill,
    paintColor: 0xff000000'u32,
    paintJoin: StrokeJoin.miter,
    paintCap: StrokeCap.butt,
    paintBlendMode: BlendMode.srcOver)

method decodeImage*(factory: NoOpFactory;
    compressedBytes: openArray[byte]): RenderImage =
  discard factory
  discard compressedBytes
  nil

method prepareEmbeddedPng*(factory: NoOpFactory; assetIndex: uint32;
    name: string; compressedBytes: openArray[byte]; expectedWidth,
    expectedHeight: uint32): SplineyResult[PreparedImage] =
  discard name
  discard compressedBytes
  let image = NoOpRenderImage(assetIndex: assetIndex)
  image.configureImage(expectedWidth.int, expectedHeight.int)
  inc factory.preparedCount
  ok[PreparedImage](image)

method releasePreparedImage*(factory: NoOpFactory;
    image: PreparedImage): SplineyStatus =
  if image of NoOpRenderImage:
    let concrete = NoOpRenderImage(image)
    if not concrete.released:
      concrete.released = true
      inc factory.releasedCount
  okStatus()

proc imageId(image: RenderImage): uint32 =
  if image of NoOpRenderImage: NoOpRenderImage(image).assetIndex else: 0'u32

proc copyFloats(buffer: RenderBuffer; count: int): seq[float32] =
  if not (buffer of NoOpRenderBuffer) or count <= 0: return
  let concrete = NoOpRenderBuffer(buffer)
  let available = concrete.bytes.len div sizeof(float32)
  let copied = min(count, available)
  result = newSeq[float32](copied)
  if copied > 0:
    copyMem(addr result[0], unsafeAddr concrete.bytes[0],
      copied * sizeof(float32))

proc copyIndices(buffer: RenderBuffer; count: int): seq[uint16] =
  if not (buffer of NoOpRenderBuffer) or count <= 0: return
  let concrete = NoOpRenderBuffer(buffer)
  let available = concrete.bytes.len div sizeof(uint16)
  let copied = min(count, available)
  result = newSeq[uint16](copied)
  if copied > 0:
    copyMem(addr result[0], unsafeAddr concrete.bytes[0],
      copied * sizeof(uint16))

method save*(renderer: NoOpRenderer) =
  renderer.stack.add(renderer.state)
  renderer.commands.add(RecordedCommand(
    kind: RecordedCommandKind.save,
    transform: renderer.state.transform,
    opacity: renderer.state.opacity))

method restore*(renderer: NoOpRenderer) =
  if renderer.stack.len == 0:
    renderer.invariantErrors.add("renderer restore underflow")
  else:
    renderer.state = renderer.stack.pop()
  renderer.commands.add(RecordedCommand(
    kind: RecordedCommandKind.restore,
    transform: renderer.state.transform,
    opacity: renderer.state.opacity))

method transform*(renderer: NoOpRenderer; value: Mat2D) =
  renderer.state.transform = renderer.state.transform * value
  renderer.commands.add(RecordedCommand(
    kind: RecordedCommandKind.transform,
    transform: renderer.state.transform,
    opacity: renderer.state.opacity))

method drawPath*(renderer: NoOpRenderer; path: RenderPath;
    paint: RenderPaint) =
  var command = RecordedCommand(
    kind: RecordedCommandKind.drawPath,
    transform: renderer.state.transform,
    opacity: renderer.state.opacity,
    fillRule: path.fillRule)
  if path of NoOpRenderPath:
    let concrete = NoOpRenderPath(path)
    command.pathVerbs = concrete.raw.verbs
    command.pathPoints = newSeq[float32](concrete.raw.points.len * 2)
    for index, point in concrete.raw.points:
      command.pathPoints[index * 2] = point.x
      command.pathPoints[index * 2 + 1] = point.y
  if paint of NoOpRenderPaint:
    let concrete = NoOpRenderPaint(paint)
    command.paintStyle = concrete.paintStyle
    command.color = concrete.paintColor
    command.blendModeValue = ord(concrete.paintBlendMode).uint8
  renderer.commands.add(move(command))

method clipPath*(renderer: NoOpRenderer; path: RenderPath) =
  var command = RecordedCommand(
    kind: RecordedCommandKind.clipPath,
    transform: renderer.state.transform,
    opacity: renderer.state.opacity,
    fillRule: path.fillRule)
  if path of NoOpRenderPath:
    let concrete = NoOpRenderPath(path)
    command.pathVerbs = concrete.raw.verbs
    command.pathPoints = newSeq[float32](concrete.raw.points.len * 2)
    for index, point in concrete.raw.points:
      command.pathPoints[index * 2] = point.x
      command.pathPoints[index * 2 + 1] = point.y
  renderer.commands.add(move(command))

method drawImage*(renderer: NoOpRenderer; image: RenderImage;
    sampler: ImageSampler; blendMode: BlendMode; opacity: float32) =
  renderer.commands.add(RecordedCommand(
    kind: RecordedCommandKind.drawImage,
    transform: renderer.state.transform,
    opacity: renderer.state.opacity * opacity,
    resourceId: image.imageId,
    samplerKey: sampler.asKey,
    blendModeValue: ord(blendMode).uint8))

method drawImageMesh*(renderer: NoOpRenderer; image: RenderImage;
    sampler: ImageSampler; vertices, uvCoords, indices: RenderBuffer;
    vertexCount, indexCount: uint32; blendMode: BlendMode;
    opacity: float32) =
  if vertices.bufferType != RenderBufferType.vertex or
      uvCoords.bufferType != RenderBufferType.vertex or
      indices.bufferType != RenderBufferType.index:
    renderer.invariantErrors.add("mesh buffer type mismatch")
  var copiedVertices = vertices.copyFloats(vertexCount.int * 2)
  var copiedUvCoords = uvCoords.copyFloats(vertexCount.int * 2)
  var copiedIndices = indices.copyIndices(indexCount.int)
  if copiedVertices.len != vertexCount.int * 2 or
      copiedUvCoords.len != vertexCount.int * 2 or
      copiedIndices.len != indexCount.int:
    renderer.invariantErrors.add("mesh buffer size mismatch")
  renderer.commands.add(RecordedCommand(
    kind: RecordedCommandKind.drawImageMesh,
    transform: renderer.state.transform,
    opacity: renderer.state.opacity * opacity,
    resourceId: image.imageId,
    samplerKey: sampler.asKey,
    blendModeValue: ord(blendMode).uint8,
    vertices: move(copiedVertices),
    uvCoords: move(copiedUvCoords),
    indices: move(copiedIndices)))

method modulateOpacity*(renderer: NoOpRenderer; opacity: float32) =
  renderer.state.opacity *= opacity
  renderer.commands.add(RecordedCommand(
    kind: RecordedCommandKind.modulateOpacity,
    transform: renderer.state.transform,
    opacity: renderer.state.opacity))

proc stackDepth*(renderer: NoOpRenderer): int = renderer.stack.len

proc reset*(renderer: NoOpRenderer) =
  renderer.commands.setLen(0)
  renderer.stack.setLen(0)
  renderer.invariantErrors.setLen(0)
  renderer.state = RendererState(transform: IdentityMat2D, opacity: 1)

proc appendU32(bytes: var seq[byte]; value: uint32) =
  bytes.add(byte(value and 0xff))
  bytes.add(byte((value shr 8) and 0xff))
  bytes.add(byte((value shr 16) and 0xff))
  bytes.add(byte((value shr 24) and 0xff))

proc appendU16(bytes: var seq[byte]; value: uint16) =
  bytes.add(byte(value and 0xff))
  bytes.add(byte((value shr 8) and 0xff))

proc appendF32(bytes: var seq[byte]; value: float32) =
  bytes.appendU32(cast[uint32](value))

proc canonicalBytes*(renderer: NoOpRenderer): seq[byte] =
  ## Fixed-width little-endian encoding suitable for an external SHA-256.
  result.appendU32(renderer.commands.len.uint32)
  for command in renderer.commands:
    result.add(ord(command.kind).byte)
    for value in command.transform.values: result.appendF32(value)
    result.appendF32(command.opacity)
    result.appendU32(command.resourceId)
    result.add(command.samplerKey)
    result.add(command.blendModeValue)
    result.add(ord(command.fillRule).byte)
    result.add(ord(command.paintStyle).byte)
    result.appendU32(command.color)
    result.appendU32(command.pathVerbs.len.uint32)
    for value in command.pathVerbs: result.add(ord(value).byte)
    result.appendU32(command.pathPoints.len.uint32)
    for value in command.pathPoints: result.appendF32(value)
    result.appendU32(command.vertices.len.uint32)
    for value in command.vertices: result.appendF32(value)
    result.appendU32(command.uvCoords.len.uint32)
    for value in command.uvCoords: result.appendF32(value)
    result.appendU32(command.indices.len.uint32)
    for value in command.indices: result.appendU16(value)
