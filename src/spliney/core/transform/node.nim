## Immutable Node definitions and independent mutable transform instances.

import std/[parseutils, tables]

import spliney/errors
import spliney/generated/wire_registry
import spliney/io/loader
import spliney/math/geometry

type
  NodeDefinition* = ref object
    objectId*: uint32
    typeKey*: uint32
    name*: string
    parentId*: uint32
    x*, y*: float32
    rotation*: float32
    scaleX*, scaleY*: float32
    opacity*: float32

  NodeInstance* = ref object
    definition*: NodeDefinition
    parent*: NodeInstance
    x*, y*: float32
    rotation*: float32
    scaleX*, scaleY*: float32
    opacity*: float32
    localTransform*: Mat2D
    worldTransform*: Mat2D
    renderOpacity*: float32

proc inheritsFrom*(typeKey, ancestorKey: uint32): bool =
  var current = typeKey
  while current != 0:
    if current == ancestorKey: return true
    let metadata = typeMetadata(current)
    if metadata.isNil: return false
    current = metadata.parentKey

proc constructionError(message: string; typeKey: uint32; propertyKey = -1'i32):
    SplineyError =
  SplineyError(
    category: ErrorCategory.resolution,
    stage: ErrorStage.referenceResolution,
    message: message,
    context: ErrorContext(
      objectTypeKey: typeKey.int32,
      propertyKey: propertyKey,
      assetId: -1,
      animationIndex: -1))

proc floatProperty(item: WireObject; key: uint32): SplineyResult[float32] =
  let lookup = item.propertyOrDefault(key)
  if not lookup.found:
    return err[float32](constructionError(
      "missing generated float metadata", item.typeKey, key.int32))
  if lookup.serialized:
    if lookup.value.kind != WireKind.floatValue:
      return err[float32](constructionError(
        "transform property has wrong wire kind", item.typeKey, key.int32))
    return ok(lookup.value.floatValue)
  var value: float
  if parseFloat(lookup.defaultText, value) == 0:
    return err[float32](constructionError(
      "transform default is not numeric", item.typeKey, key.int32))
  ok(value.float32)

proc uintProperty(item: WireObject; key: uint32): SplineyResult[uint32] =
  let lookup = item.propertyOrDefault(key)
  if not lookup.found:
    return err[uint32](constructionError(
      "missing generated uint metadata", item.typeKey, key.int32))
  if lookup.serialized:
    if lookup.value.kind != WireKind.uintValue or
        lookup.value.uintValue > high(uint32).uint64:
      return err[uint32](constructionError(
        "transform reference has wrong wire value", item.typeKey, key.int32))
    return ok(lookup.value.uintValue.uint32)
  var value: uint
  if parseUInt(lookup.defaultText, value) == 0 or value > high(uint32).uint:
    return err[uint32](constructionError(
      "transform uint default is invalid", item.typeKey, key.int32))
  ok(value.uint32)

proc stringProperty(item: WireObject; key: uint32): SplineyResult[string] =
  let lookup = item.propertyOrDefault(key)
  if not lookup.found:
    return err[string](constructionError(
      "missing generated string metadata", item.typeKey, key.int32))
  if lookup.serialized:
    if lookup.value.kind != WireKind.stringValue:
      return err[string](constructionError(
        "transform name has wrong wire kind", item.typeKey, key.int32))
    return ok(lookup.value.dataValue)
  var default = lookup.defaultText
  if default == "''" or default == "\"\"": default = ""
  ok(default)

proc nodeDefinition*(item: WireObject; objectId: uint32):
    SplineyResult[NodeDefinition] =
  if not item.typeKey.inheritsFrom(2):
    return err[NodeDefinition](constructionError(
      "object is not a Node", item.typeKey))
  let name = item.stringProperty(4)
  if not name.isOk: return err[NodeDefinition](name.error)
  let parentId = item.uintProperty(5)
  if not parentId.isOk: return err[NodeDefinition](parentId.error)
  let x = item.floatProperty(13)
  if not x.isOk: return err[NodeDefinition](x.error)
  let y = item.floatProperty(14)
  if not y.isOk: return err[NodeDefinition](y.error)
  let rotation = item.floatProperty(15)
  if not rotation.isOk: return err[NodeDefinition](rotation.error)
  let scaleX = item.floatProperty(16)
  if not scaleX.isOk: return err[NodeDefinition](scaleX.error)
  let scaleY = item.floatProperty(17)
  if not scaleY.isOk: return err[NodeDefinition](scaleY.error)
  let opacity = item.floatProperty(18)
  if not opacity.isOk: return err[NodeDefinition](opacity.error)
  ok(NodeDefinition(
    objectId: objectId,
    typeKey: item.typeKey,
    name: name.value,
    parentId: parentId.value,
    x: x.value,
    y: y.value,
    rotation: rotation.value,
    scaleX: scaleX.value,
    scaleY: scaleY.value,
    opacity: opacity.value))

proc newNodeInstance*(definition: NodeDefinition): NodeInstance =
  NodeInstance(
    definition: definition,
    x: definition.x,
    y: definition.y,
    rotation: definition.rotation,
    scaleX: definition.scaleX,
    scaleY: definition.scaleY,
    opacity: definition.opacity,
    localTransform: IdentityMat2D,
    worldTransform: IdentityMat2D,
    renderOpacity: 1)

proc updateLocal*(node: NodeInstance) =
  node.localTransform = rotationMat2D(node.rotation) *
    scaleMat2D(node.scaleX, node.scaleY)
  node.localTransform.values[4] = node.x
  node.localTransform.values[5] = node.y

proc updateWorld*(node: NodeInstance) =
  node.updateLocal()
  if node.parent.isNil:
    node.worldTransform = node.localTransform
    node.renderOpacity = node.opacity
  else:
    node.worldTransform = node.parent.worldTransform * node.localTransform
    node.renderOpacity = node.parent.renderOpacity * node.opacity

proc linkAndUpdate*(nodes: openArray[NodeInstance]): SplineyStatus =
  var byId = initTable[uint32, NodeInstance]()
  for node in nodes:
    if node.isNil or node.definition.isNil:
      return errStatus(constructionError("nil transform instance", 2))
    if byId.hasKey(node.definition.objectId):
      return errStatus(constructionError("duplicate component id",
        node.definition.typeKey))
    byId[node.definition.objectId] = node
  for node in nodes:
    if node.definition.parentId == 0:
      node.parent = nil
    elif byId.hasKey(node.definition.parentId):
      node.parent = byId[node.definition.parentId]
    else:
      return errStatus(constructionError("missing transform parent",
        node.definition.typeKey, 5))

  var marks = initTable[uint32, uint8]()
  proc visit(node: NodeInstance): bool =
    let id = node.definition.objectId
    case marks.getOrDefault(id)
    of 1: return false
    of 2: return true
    else: discard
    marks[id] = 1
    if not node.parent.isNil and not visit(node.parent): return false
    node.updateWorld()
    marks[id] = 2
    true
  for node in nodes:
    if not visit(node):
      return errStatus(constructionError("transform parent cycle",
        node.definition.typeKey, 5))
  okStatus()
