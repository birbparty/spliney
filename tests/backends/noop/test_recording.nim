import std/[sequtils, unittest]

import spliney/backends/noop/recording
import spliney/math/geometry
import spliney/render/protocol

proc writeFloats(buffer: RenderBuffer; values: openArray[float32]) =
  let destination = cast[ptr UncheckedArray[float32]](buffer.map())
  for index, value in values: destination[index] = value
  buffer.unmap()

proc writeIndices(buffer: RenderBuffer; values: openArray[uint16]) =
  let destination = cast[ptr UncheckedArray[uint16]](buffer.map())
  for index, value in values: destination[index] = value
  buffer.unmap()

suite "no-op recording backend":
  test "records state commands and restores transform and opacity":
    let renderer = newNoOpRenderer()
    renderer.save()
    renderer.translate(10, 20)
    renderer.modulateOpacity(0.5)
    renderer.restore()
    check renderer.stackDepth == 0
    check renderer.invariantErrors.len == 0
    check renderer.commands.mapIt(it.kind) == @[
      RecordedCommandKind.save,
      RecordedCommandKind.transform,
      RecordedCommandKind.modulateOpacity,
      RecordedCommandKind.restore]
    check renderer.commands[^1].transform == IdentityMat2D
    check renderer.commands[^1].opacity == 1

  test "snapshots indexed mesh buffers and effective opacity":
    let factory = newNoOpFactory()
    let renderer = newNoOpRenderer()
    let image = NoOpRenderImage(assetIndex: 7)
    image.configureImage(16, 8)
    let vertices = factory.makeRenderBuffer(RenderBufferType.vertex, {}, 24)
    let uvs = factory.makeRenderBuffer(RenderBufferType.vertex, {}, 24)
    let indices = factory.makeRenderBuffer(RenderBufferType.index, {}, 6)
    vertices.writeFloats([0'f32, 0, 1, 0, 0, 1])
    uvs.writeFloats([0'f32, 0, 1, 0, 0, 1])
    indices.writeIndices([0'u16, 1, 2])
    renderer.modulateOpacity(0.5)
    renderer.drawImageMesh(image, LinearClampSampler,
      vertices, uvs, indices, 3, 3, BlendMode.srcOver, 0.4)
    check renderer.invariantErrors.len == 0
    let command = renderer.commands[^1]
    check command.kind == RecordedCommandKind.drawImageMesh
    check command.resourceId == 7
    check command.opacity == 0.2'f32
    check command.vertices == @[0'f32, 0, 1, 0, 0, 1]
    check command.indices == @[0'u16, 1, 2]

  test "canonical bytes are deterministic and argument-sensitive":
    let first = newNoOpRenderer()
    first.translate(1, 2)
    let second = newNoOpRenderer()
    second.translate(1, 2)
    check first.canonicalBytes == second.canonicalBytes
    second.modulateOpacity(0.5)
    check first.canonicalBytes != second.canonicalBytes

  test "factory resources are acquired and released once":
    let factory = newNoOpFactory()
    let prepared = factory.prepareEmbeddedPng(4, "fixture", [1'u8, 2], 3, 5)
    require prepared.isOk
    check factory.preparedCount == 1
    let image = RenderImage(prepared.value)
    check image.width == 3
    check image.height == 5
    discard factory.releasePreparedImage(prepared.value)
    discard factory.releasePreparedImage(prepared.value)
    check factory.releasedCount == 1

  test "reports restore underflow without corrupting later recording":
    let renderer = newNoOpRenderer()
    renderer.restore()
    renderer.save()
    renderer.restore()
    check renderer.invariantErrors == @["renderer restore underflow"]
    check renderer.stackDepth == 0
