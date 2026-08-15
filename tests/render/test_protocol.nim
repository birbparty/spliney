import std/unittest

import spliney/math/geometry
import spliney/render/protocol

type
  CountingRenderer = ref object of Renderer
    calls: seq[string]

method save(renderer: CountingRenderer) = renderer.calls.add("save")
method restore(renderer: CountingRenderer) = renderer.calls.add("restore")
method transform(renderer: CountingRenderer; value: Mat2D) =
  renderer.calls.add("transform:" & $value.values[4] & ":" & $value.values[5])
method drawPath(renderer: CountingRenderer; path: RenderPath;
    paint: RenderPaint) =
  discard path
  discard paint
  renderer.calls.add("path")
method clipPath(renderer: CountingRenderer; path: RenderPath) =
  discard path
  renderer.calls.add("clip")
method drawImage(renderer: CountingRenderer; image: RenderImage;
    sampler: ImageSampler; blendMode: BlendMode; opacity: float32) =
  discard image
  discard sampler
  discard blendMode
  renderer.calls.add("image:" & $opacity)
method drawImageMesh(renderer: CountingRenderer; image: RenderImage;
    sampler: ImageSampler; vertices, uvCoords, indices: RenderBuffer;
    vertexCount, indexCount: uint32; blendMode: BlendMode; opacity: float32) =
  discard image
  discard sampler
  discard vertices
  discard uvCoords
  discard indices
  discard blendMode
  renderer.calls.add("mesh:" & $vertexCount & ":" & $indexCount & ":" & $opacity)
method modulateOpacity(renderer: CountingRenderer; opacity: float32) =
  renderer.calls.add("opacity:" & $opacity)

suite "renderer protocol":
  test "dispatches all eight renderer operations in stable order":
    let concrete = CountingRenderer()
    let renderer: Renderer = concrete
    let path = RenderPath(fillRule: FillRule.evenOdd)
    let paint = RenderPaint()
    let image = RenderImage()
    image.configureImage(64, 32)
    let buffer = RenderBuffer(bufferType: RenderBufferType.vertex,
      sizeInBytes: 16)
    renderer.save()
    renderer.transform(IdentityMat2D)
    renderer.drawPath(path, paint)
    renderer.clipPath(path)
    renderer.drawImage(image, LinearClampSampler, BlendMode.srcOver, 0.5)
    renderer.drawImageMesh(image, LinearClampSampler, buffer, buffer, buffer,
      4, 6, BlendMode.srcOver, 0.25)
    renderer.modulateOpacity(0.75)
    renderer.restore()
    check concrete.calls == @["save", "transform:0.0:0.0", "path", "clip",
      "image:0.5", "mesh:4:6:0.25", "opacity:0.75", "restore"]

  test "matches Rive image sampler key packing":
    for key in 0'u8 .. 17'u8:
      check samplerFromKey(key).asKey == key
    check LinearClampSampler.asKey == 0

  test "renderer transform helpers concatenate explicit matrices":
    let concrete = CountingRenderer()
    let renderer: Renderer = concrete
    renderer.translate(3, 4)
    renderer.scale(2, 5)
    renderer.rotate(0)
    check concrete.calls == @["transform:3.0:4.0", "transform:0.0:0.0",
      "transform:0.0:0.0"]

  test "render image metadata is immutable through accessors":
    let image = RenderImage()
    image.configureImage(320, 200, scaleMat2D(0.5, 0.25))
    check image.width == 320
    check image.height == 200
    check image.uvTransform == scaleMat2D(0.5, 0.25)
