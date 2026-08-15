import std/unittest

import spliney/generated/wire_registry
import spliney/io/loader
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
