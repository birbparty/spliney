import std/unittest

import spliney/core/transform/node
import spliney/generated/wire_registry
import spliney/io/loader
import spliney/math/geometry

proc property(key: uint32; value: WireValue): WireProperty =
  WireProperty(key: key, value: value)

proc floatValue(value: float32): WireValue =
  WireValue(kind: WireKind.floatValue, floatValue: value)
proc uintValue(value: uint64): WireValue =
  WireValue(kind: WireKind.uintValue, uintValue: value)
proc stringValue(value: string): WireValue =
  WireValue(kind: WireKind.stringValue, dataValue: value)

proc nodeWire(parentId: uint32; x, y, rotation: float32;
    name = ""): WireObject =
  WireObject(typeKey: 2, knownType: true, properties: @[
    property(4, stringValue(name)),
    property(5, uintValue(parentId)),
    property(13, floatValue(x)),
    property(14, floatValue(y)),
    property(15, floatValue(rotation))])

proc close(a, b: float32): bool = abs(a - b) <= 0.00001

suite "Node definitions and transform instances":
  test "deserialization uses generated defaults":
    let parsed = nodeDefinition(nodeWire(0, 12, -3, 0.5, "target"), 7)
    require parsed.isOk
    check parsed.value.objectId == 7
    check parsed.value.name == "target"
    check parsed.value.scaleX == 1
    check parsed.value.scaleY == 1
    check parsed.value.opacity == 1

  test "independent instances compose parent world transforms and opacity":
    let parentDefinition = nodeDefinition(nodeWire(0, 10, 20, 0), 1).value
    let childDefinition = nodeDefinition(nodeWire(1, 5, 0, 0), 2).value
    let parent = newNodeInstance(parentDefinition)
    let child = newNodeInstance(childDefinition)
    parent.opacity = 0.5
    child.opacity = 0.4
    let status = linkAndUpdate([child, parent])
    require status.isOk
    check child.parent == parent
    check child.worldTransform.values[4] == 15
    check child.worldTransform.values[5] == 20
    check child.renderOpacity.close(0.2)

    let independent = newNodeInstance(childDefinition)
    independent.x = 100
    check child.x == 5
    check childDefinition.x == 5

  test "rotation and nonuniform scale follow official local order":
    let definition = nodeDefinition(nodeWire(0, 3, 4, 0), 1).value
    let instance = newNodeInstance(definition)
    instance.rotation = 0.5
    instance.scaleX = 2
    instance.scaleY = 3
    instance.updateWorld()
    let expected = rotationMat2D(0.5) * scaleMat2D(2, 3)
    for index in 0 .. 3:
      check instance.localTransform.values[index].close(expected.values[index])
    check instance.localTransform.values[4] == 3
    check instance.localTransform.values[5] == 4

  test "linking rejects missing parents duplicates and cycles":
    let missing = newNodeInstance(nodeDefinition(nodeWire(99, 0, 0, 0), 1).value)
    check not linkAndUpdate([missing]).isOk

    let first = newNodeInstance(nodeDefinition(nodeWire(2, 0, 0, 0), 1).value)
    let second = newNodeInstance(nodeDefinition(nodeWire(1, 0, 0, 0), 2).value)
    let cycle = linkAndUpdate([first, second])
    check not cycle.isOk
    check cycle.error.message == "transform parent cycle"

    let duplicate = newNodeInstance(first.definition)
    check not linkAndUpdate([first, duplicate]).isOk

  test "non-Node wire objects are rejected structurally":
    let invalid = nodeDefinition(WireObject(typeKey: 18, knownType: true), 1)
    check not invalid.isOk
    check invalid.error.message == "object is not a Node"
