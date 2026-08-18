## Direct rlgl Renderer selected by ADR 0002 for macOS.

when not defined(useNaylib):
  {.error: "spliney/backends/raylib/renderer requires -d:useNaylib".}

import std/math

import raylib
import rlgl

import spliney/adapters/raylib_images
import spliney/errors
import spliney/math/geometry
import spliney/render/protocol

export raylib_images

type
  RaylibRenderBuffer* = ref object of RenderBuffer
    bytes: seq[byte]

  RaylibRenderPath* = ref object of RenderPath
    raw: RawPath

  RaylibRenderPaint* = ref object of RenderPaint
    paintStyle: RenderPaintStyle
    paintColor: ColorInt
    paintBlendMode: protocol.BlendMode

  RaylibRendererState = object
    transform: Mat2D
    opacity: float32

  RaylibRenderer* = ref object of Renderer
    # Keeps raylib.h ahead of rlgl.h in Nim's generated translation unit.
    raylibHeaderOrder: raylib.Color
    state: RaylibRendererState
    stack: seq[RaylibRendererState]
    failure: SplineyError
    failed: bool
    frameActive: bool

proc newRaylibFactory*(): RaylibFactory = RaylibFactory()

proc newRaylibRenderer*(): RaylibRenderer =
  RaylibRenderer(state: RaylibRendererState(
    transform: IdentityMat2D,
    opacity: 1'f32))

proc fail(renderer: RaylibRenderer; message: string; assetId = -1'i64) =
  if renderer.failed: return
  renderer.failed = true
  renderer.failure = SplineyError(
    category: ErrorCategory.render,
    stage: ErrorStage.drawSubmission,
    message: message,
    context: ErrorContext(objectTypeKey: -1, propertyKey: -1,
      assetId: assetId, animationIndex: -1))

method onMap*(buffer: RaylibRenderBuffer): pointer =
  if buffer.bytes.len == 0: nil else: addr buffer.bytes[0]

method onUnmap*(buffer: RaylibRenderBuffer) = discard buffer

method makeRenderBuffer*(factory: RaylibImageFactory;
    bufferType: RenderBufferType; flags: RenderBufferFlags;
    sizeInBytes: int): RenderBuffer =
  discard factory
  RaylibRenderBuffer(
    bufferType: bufferType,
    flags: flags,
    sizeInBytes: sizeInBytes,
    bytes: newSeq[byte](sizeInBytes))

method makeRenderPath*(factory: RaylibImageFactory; raw: var RawPath;
    fillRule: FillRule): RenderPath =
  discard factory
  RaylibRenderPath(fillRule: fillRule, raw: move(raw))

method makeEmptyRenderPath*(factory: RaylibImageFactory): RenderPath =
  discard factory
  RaylibRenderPath(fillRule: FillRule.nonZero)

method makeRenderPaint*(factory: RaylibImageFactory): RenderPaint =
  discard factory
  RaylibRenderPaint(
    paintStyle: RenderPaintStyle.fill,
    paintColor: 0xff000000'u32,
    paintBlendMode: protocol.BlendMode.srcOver)

method style*(paint: RaylibRenderPaint; value: RenderPaintStyle) =
  paint.paintStyle = value
method color*(paint: RaylibRenderPaint; value: ColorInt) =
  paint.paintColor = value
method blendMode*(paint: RaylibRenderPaint; value: protocol.BlendMode) =
  paint.paintBlendMode = value

proc transformed(matrix: Mat2D; x, y: float32): Vec2D =
  matrix * vec2(x, y)

proc isFinite(value: float32): bool =
  classify(value) notin {fcNan, fcInf, fcNegInf}

proc opacityByte(value: float32): uint8 =
  round(clamp(value, 0'f32, 1'f32) * 255'f32).uint8

proc submitVertex(position, uv: Vec2D; opacity: uint8) =
  texCoord2f(uv.x, uv.y)
  color4ub(255, 255, 255, opacity)
  vertex2f(position.x, position.y)

proc submitTexturedTriangles(renderer: RaylibRenderer;
    image: RaylibPreparedImage; vertices, uvCoords: ptr UncheckedArray[float32];
    indices: ptr UncheckedArray[uint16]; vertexCount, indexCount: int;
    opacity: float32) =
  if renderer.failed: return
  if vertexCount <= 0 or indexCount <= 0 or indexCount mod 3 != 0:
    renderer.fail("mesh has invalid vertex or triangle counts",
      image.assetIndex.int64)
    return
  if not opacity.isFinite:
    renderer.fail("mesh opacity is not finite", image.assetIndex.int64)
    return
  setTexture(image.texture.id)
  rlBegin(Triangles)
  let alpha = opacity.opacityByte
  for index in 0 ..< indexCount:
    let vertexIndex = indices[index].int
    if vertexIndex < 0 or vertexIndex >= vertexCount:
      rlEnd()
      setTexture(0)
      renderer.fail("mesh index is outside vertex buffer", image.assetIndex.int64)
      return
    let x = vertices[vertexIndex * 2]
    let y = vertices[vertexIndex * 2 + 1]
    let u = uvCoords[vertexIndex * 2]
    let v = uvCoords[vertexIndex * 2 + 1]
    if not x.isFinite or not y.isFinite or not u.isFinite or not v.isFinite:
      rlEnd()
      setTexture(0)
      renderer.fail("mesh contains non-finite coordinates",
        image.assetIndex.int64)
      return
    let position = renderer.state.transform.transformed(x, y)
    if not position.x.isFinite or not position.y.isFinite:
      rlEnd()
      setTexture(0)
      renderer.fail("mesh transform produced non-finite coordinates",
        image.assetIndex.int64)
      return
    position.submitVertex(vec2(u, v), alpha)
  rlEnd()
  setTexture(0)

method save*(renderer: RaylibRenderer) =
  if renderer.stack.len == 0:
    setBlendFactorsSeparate(SrcAlpha, OneMinusSrcAlpha, One,
      OneMinusSrcAlpha, FuncAdd, FuncAdd)
    setBlendMode(CustomSeparate)
    disableBackfaceCulling()
    renderer.frameActive = true
  renderer.stack.add(renderer.state)

method restore*(renderer: RaylibRenderer) =
  if renderer.stack.len == 0:
    renderer.fail("renderer restore underflow")
    return
  renderer.state = renderer.stack.pop()
  if renderer.stack.len == 0 and renderer.frameActive:
    drawRenderBatchActive()
    enableBackfaceCulling()
    setBlendMode(Alpha)
    renderer.frameActive = false

method transform*(renderer: RaylibRenderer; value: Mat2D) =
  for component in value.values:
    if not component.isFinite:
      renderer.fail("renderer transform is not finite")
      return
  renderer.state.transform = renderer.state.transform * value

method drawPath*(renderer: RaylibRenderer; path: RenderPath;
    paint: RenderPaint) =
  if renderer.failed: return
  if not (path of RaylibRenderPath) or not (paint of RaylibRenderPaint):
    renderer.fail("Raylib path or paint resource has the wrong backend type")
    return
  let concretePath = RaylibRenderPath(path)
  let concretePaint = RaylibRenderPaint(paint)
  if concretePaint.paintStyle != RenderPaintStyle.fill or
      concretePath.raw.points.len != 4:
    renderer.fail("Raylib exact path slice supports one convex quad fill")
    return
  if concretePaint.paintBlendMode != protocol.BlendMode.srcOver:
    renderer.fail("unsupported exact path blend mode")
    return
  let argb = concretePaint.paintColor
  let alpha = ((argb shr 24) and 0xff).uint8
  let red = ((argb shr 16) and 0xff).uint8
  let green = ((argb shr 8) and 0xff).uint8
  let blue = (argb and 0xff).uint8
  let effectiveAlpha = round(alpha.float32 *
    clamp(renderer.state.opacity, 0'f32, 1'f32)).uint8
  const indices = [0, 1, 2, 0, 2, 3]
  setTexture(0)
  rlBegin(Triangles)
  for index in indices:
    let position = renderer.state.transform * concretePath.raw.points[index]
    if not position.x.isFinite or not position.y.isFinite:
      rlEnd()
      renderer.fail("path transform produced non-finite coordinates")
      return
    color4ub(red, green, blue, effectiveAlpha)
    vertex2f(position.x, position.y)
  rlEnd()

method clipPath*(renderer: RaylibRenderer; path: RenderPath) =
  discard path
  renderer.fail("clip paths are outside the exact Raylib slice")

method drawImage*(renderer: RaylibRenderer; image: RenderImage;
    sampler: ImageSampler; blendMode: protocol.BlendMode; opacity: float32) =
  if renderer.failed: return
  if not (image of RaylibPreparedImage):
    renderer.fail("Raylib image resource has the wrong backend type")
    return
  if sampler != LinearClampSampler or blendMode != protocol.BlendMode.srcOver:
    renderer.fail("unsupported exact image sampler or blend mode")
    return
  let prepared = RaylibPreparedImage(image)
  if prepared.released or not prepared.textureReady:
    renderer.fail("Raylib image texture is not live", prepared.assetIndex.int64)
    return
  let vertices = [0'f32, 0, image.width.float32, 0,
    image.width.float32, image.height.float32, 0, image.height.float32]
  let uvs = [0'f32, 0, 1, 0, 1, 1, 0, 1]
  let indices = [0'u16, 1, 2, 0, 2, 3]
  renderer.submitTexturedTriangles(prepared,
    cast[ptr UncheckedArray[float32]](unsafeAddr vertices[0]),
    cast[ptr UncheckedArray[float32]](unsafeAddr uvs[0]),
    cast[ptr UncheckedArray[uint16]](unsafeAddr indices[0]),
    4, 6, renderer.state.opacity * opacity)

method drawImageMesh*(renderer: RaylibRenderer; image: RenderImage;
    sampler: ImageSampler; vertices, uvCoords, indices: RenderBuffer;
    vertexCount, indexCount: uint32; blendMode: protocol.BlendMode;
    opacity: float32) =
  if renderer.failed: return
  if not (image of RaylibPreparedImage) or
      not (vertices of RaylibRenderBuffer) or
      not (uvCoords of RaylibRenderBuffer) or
      not (indices of RaylibRenderBuffer):
    renderer.fail("Raylib mesh resource has the wrong backend type")
    return
  if sampler != LinearClampSampler or blendMode != protocol.BlendMode.srcOver:
    renderer.fail("unsupported exact mesh sampler or blend mode")
    return
  let prepared = RaylibPreparedImage(image)
  let positionBuffer = RaylibRenderBuffer(vertices)
  let uvBuffer = RaylibRenderBuffer(uvCoords)
  let indexBuffer = RaylibRenderBuffer(indices)
  if prepared.released or not prepared.textureReady:
    renderer.fail("Raylib image texture is not live", prepared.assetIndex.int64)
    return
  if positionBuffer.bytes.len < vertexCount.int * 2 * sizeof(float32) or
      uvBuffer.bytes.len < vertexCount.int * 2 * sizeof(float32) or
      indexBuffer.bytes.len < indexCount.int * sizeof(uint16):
    renderer.fail("Raylib mesh buffer is smaller than its declared count",
      prepared.assetIndex.int64)
    return
  renderer.submitTexturedTriangles(prepared,
    cast[ptr UncheckedArray[float32]](unsafeAddr positionBuffer.bytes[0]),
    cast[ptr UncheckedArray[float32]](unsafeAddr uvBuffer.bytes[0]),
    cast[ptr UncheckedArray[uint16]](unsafeAddr indexBuffer.bytes[0]),
    vertexCount.int, indexCount.int, renderer.state.opacity * opacity)

method modulateOpacity*(renderer: RaylibRenderer; opacity: float32) =
  if not opacity.isFinite:
    renderer.fail("renderer opacity is not finite")
    return
  renderer.state.opacity *= opacity

method renderStatus*(renderer: RaylibRenderer): SplineyStatus =
  if renderer.failed: errStatus(renderer.failure) else: okStatus()

proc reset*(renderer: RaylibRenderer) =
  doAssert renderer.stack.len == 0 and not renderer.frameActive
  renderer.state = RaylibRendererState(transform: IdentityMat2D, opacity: 1)
  renderer.failed = false
  renderer.failure = default(SplineyError)
