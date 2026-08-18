import std/[sequtils, unittest]

import spliney/backends/noop/recording
import spliney/generated/wire_registry
import spliney/io/loader
import spliney/math/geometry
import spliney/render/protocol
import spliney/scene/exact_runtime

proc property(key: uint32; value: WireValue): WireProperty =
  WireProperty(key: key, value: value)

proc uintValue(value: uint64): WireValue =
  WireValue(kind: WireKind.uintValue, uintValue: value)

proc floatValue(value: float32): WireValue =
  WireValue(kind: WireKind.floatValue, floatValue: value)

proc stringValue(value: string; kind = WireKind.stringValue): WireValue =
  WireValue(kind: kind, dataValue: value)

suite "exact mesh and constraint runtime":
  test "embedded image definitions retain compressed bytes in source order":
    let pngHeader = "\x89PNG\r\n\x1a\n"
    let wire = WireFile(objects: @[
      WireObject(typeKey: 105, knownType: true, properties: @[
        property(203, stringValue("image")),
        property(207, floatValue(20)),
        property(208, floatValue(10))]),
      WireObject(typeKey: 106, knownType: true, properties: @[
        property(212, stringValue(pngHeader, WireKind.bytesValue))])])
    let assets = importEmbeddedImages(wire)
    require assets.isOk
    check assets.value.len == 1
    check assets.value[0].index == 0
    check assets.value[0].name == "image"
    check assets.value[0].width == 10
    check assets.value[0].height == 20
    check assets.value[0].compressedBytes == pngHeader

  test "invalid constraint references fail during scene construction":
    let wire = WireFile(objects: @[
      WireObject(typeKey: 1, knownType: true),
      WireObject(typeKey: 2, knownType: true),
      WireObject(typeKey: 83, knownType: true, properties: @[
        property(5, uintValue(1)),
        property(173, uintValue(99))])])
    let scene = newExactScene(wire, [0'u32, 1, 2])
    check not scene.isOk
    check scene.error.message == "constraint target is invalid"

  test "mesh indices are checked against resolved vertices":
    let wire = WireFile(objects: @[
      WireObject(typeKey: 105, knownType: true, properties: @[
        property(203, stringValue("image")),
        property(207, floatValue(20)),
        property(208, floatValue(10))]),
      WireObject(typeKey: 106, knownType: true, properties: @[
        property(212, stringValue("png", WireKind.bytesValue))]),
      WireObject(typeKey: 1, knownType: true),
      WireObject(typeKey: 100, knownType: true, properties: @[
        property(206, uintValue(0))]),
      WireObject(typeKey: 109, knownType: true, properties: @[
        property(5, uintValue(1)),
        property(223, stringValue("\x00", WireKind.bytesValue))])])
    let scene = newExactScene(wire, [2'u32, 3, 4])
    check not scene.isOk
    check scene.error.message == "mesh index is out of range"

  test "solid fill and indexed mesh emission is stable and stack balanced":
    let fill = ExactComponent(objectId: 3, typeKey: 20, fillRuleValue: 2)
    let solid = ExactComponent(objectId: 4, typeKey: 18,
      colorValue: 0xff282828'u32, parent: fill)
    fill.children.add(solid)
    let imageComponent = ExactComponent(
      objectId: 1,
      typeKey: 100,
      assetId: 0,
      blendMode: 3,
      renderOpacity: 0.5,
      worldTransform: translationMat2D(5, 10),
      originX: 0.5,
      originY: 0.5)
    let mesh = ExactComponent(
      objectId: 2,
      typeKey: 109,
      parent: imageComponent,
      vertices: @[
        ExactComponent(renderTranslation: vec2(0, 0), u: 0, v: 0),
        ExactComponent(renderTranslation: vec2(2, 0), u: 1, v: 0),
        ExactComponent(renderTranslation: vec2(0, 3), u: 0, v: 1)],
      triangleIndices: @[0'u16, 1, 2])
    imageComponent.mesh = mesh
    let scene = ExactScene(
      components: @[ExactComponent(objectId: 0, typeKey: 1),
        imageComponent, mesh, fill, solid],
      meshes: @[mesh],
      solidFill: fill,
      fillPaintSource: solid)
    let factory = newNoOpFactory()
    let image = NoOpRenderImage(assetIndex: 0)
    image.configureImage(10, 20)
    let first = newNoOpRenderer()
    let bounds = aabb(0, 0, 100, 100)
    require scene.emitDrawCommands(factory, first, [RenderImage(image)],
      bounds, IdentityMat2D).isOk
    check first.stackDepth == 0
    check first.invariantErrors.len == 0
    check first.commands.filterIt(it.kind == RecordedCommandKind.drawPath).len == 1
    let meshes = first.commands.filterIt(
      it.kind == RecordedCommandKind.drawImageMesh)
    require meshes.len == 1
    check meshes[0].vertices == @[0'f32, 0, 2, 0, 0, 3]
    check meshes[0].uvCoords == @[0'f32, 0, 1, 0, 0, 1]
    check meshes[0].indices == @[0'u16, 1, 2]
    check meshes[0].opacity == 0.5

    let second = newNoOpRenderer()
    require scene.emitDrawCommands(factory, second, [RenderImage(image)],
      bounds, IdentityMat2D).isOk
    check second.canonicalBytes == first.canonicalBytes
