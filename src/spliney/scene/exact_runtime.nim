## Exact-asset transform, constraint, skin, mesh, and embedded-image runtime.
## Transform/constraint/skinning formulas are ported from the pinned MIT-licensed
## Rive runtime identified in docs/reference/rive-runtime-reference.md.

import std/[math, parseutils, strutils, tables]

import spliney/animation/keyed/runtime
import spliney/core/transform/node
import spliney/errors
import spliney/generated/wire_registry
import spliney/io/loader
import spliney/math/geometry
import spliney/render/protocol

type
  EmbeddedImageDefinition* = ref object
    index*: uint32
    name*: string
    width*, height*: float32
    compressedBytes*: string

  ExactComponent* = ref object
    objectId*: uint32
    typeKey*: uint32
    parentId*: uint32
    name*: string
    parent*: ExactComponent
    children*: seq[ExactComponent]
    constraints*: seq[ExactComponent]

    x*, y*, rotation*, scaleX*, scaleY*, opacity*: float32
    localTransform*, worldTransform*: Mat2D
    renderOpacity*: float32
    length*: float32

    strength*: float32
    targetId*: uint32
    target*: ExactComponent
    invertDirection*: bool
    parentBoneCount*: uint32
    sourceSpace*, destSpace*: uint32
    originX*, originY*: float32

    assetId*: uint32
    imageAsset*: EmbeddedImageDefinition
    mesh*: ExactComponent
    blendMode*: uint32
    colorValue*: uint32
    fillRuleValue*: uint32

    skin*: ExactComponent
    vertices*: seq[ExactComponent]
    triangleIndices*: seq[uint16]

    vertexX*, vertexY*, u*, v*: float32
    weight*: ExactComponent
    renderTranslation*: Vec2D

    weightValues*, weightIndices*: uint32

    bindTransform*: Mat2D
    tendons*: seq[ExactComponent]
    boneTransforms*: seq[Mat2D]

    boneId*: uint32
    bone*: ExactComponent
    inverseBind*: Mat2D

    renderVertexBuffer: RenderBuffer
    renderUvBuffer: RenderBuffer
    renderIndexBuffer: RenderBuffer
    staticBuffersInitialized: bool

  ExactScene* = ref object
    components*: seq[ExactComponent]
    imageAssets*: seq[EmbeddedImageDefinition]
    meshes*: seq[ExactComponent]
    skins*: seq[ExactComponent]
    transforms*: seq[ExactComponent]
    constraints*: seq[ExactComponent]
    solidFill*: ExactComponent
    fillPaintSource*: ExactComponent
    renderFactory: Factory
    renderFillPath: RenderPath
    renderFillPaint: RenderPaint

proc exactError(message: string; stage = ErrorStage.referenceResolution;
    objectId = MissingObjectId; propertyKey = MissingObjectId;
    category = ErrorCategory.resolution): SplineyError =
  SplineyError(
    category: category,
    stage: stage,
    message: message,
    context: ErrorContext(
      label: if objectId == MissingObjectId: "" else: $objectId,
      objectTypeKey: -1,
      propertyKey: if propertyKey == MissingObjectId: -1 else: propertyKey.int32,
      assetId: -1,
      animationIndex: -1))

proc floatProperty(item: WireObject; key: uint32): SplineyResult[float32] =
  let lookup = item.propertyOrDefault(key)
  if not lookup.found:
    return err[float32](exactError("missing generated float metadata",
      ErrorStage.objectStream, propertyKey = key,
      category = ErrorCategory.malformedData))
  if lookup.serialized:
    if lookup.value.kind != WireKind.floatValue:
      return err[float32](exactError("float property has wrong wire value",
        ErrorStage.objectStream, propertyKey = key,
        category = ErrorCategory.malformedData))
    return ok(lookup.value.floatValue)
  var value: float
  if parseFloat(lookup.defaultText, value) == 0:
    return err[float32](exactError("float property default is invalid",
      ErrorStage.objectStream, propertyKey = key,
      category = ErrorCategory.malformedData))
  ok(value.float32)

proc uintProperty(item: WireObject; key: uint32;
    missingSentinel = false): SplineyResult[uint32] =
  let lookup = item.propertyOrDefault(key)
  if not lookup.found:
    return err[uint32](exactError("missing generated uint metadata",
      ErrorStage.objectStream, propertyKey = key,
      category = ErrorCategory.malformedData))
  if lookup.serialized:
    if lookup.value.kind != WireKind.uintValue or
        lookup.value.uintValue > high(uint32).uint64:
      return err[uint32](exactError("uint property has wrong wire value",
        ErrorStage.objectStream, propertyKey = key,
        category = ErrorCategory.malformedData))
    return ok(lookup.value.uintValue.uint32)
  if missingSentinel and lookup.defaultText == "-1":
    return ok(MissingObjectId)
  if lookup.defaultText == "true": return ok(1'u32)
  if lookup.defaultText == "false": return ok(0'u32)
  var value: uint
  if parseUInt(lookup.defaultText, value) == 0 or value > high(uint32).uint:
    return err[uint32](exactError("uint property default is invalid",
      ErrorStage.objectStream, propertyKey = key,
      category = ErrorCategory.malformedData))
  ok(value.uint32)

proc colorProperty(item: WireObject; key: uint32): SplineyResult[uint32] =
  let lookup = item.propertyOrDefault(key)
  if not lookup.found:
    return err[uint32](exactError("missing generated color metadata",
      ErrorStage.objectStream, propertyKey = key,
      category = ErrorCategory.malformedData))
  if lookup.serialized:
    if lookup.value.kind != WireKind.colorValue:
      return err[uint32](exactError("color property has wrong wire value",
        ErrorStage.objectStream, propertyKey = key,
        category = ErrorCategory.malformedData))
    return ok(lookup.value.colorValue)
  var value: uint
  let start = if lookup.defaultText.startsWith("0x"): 2 else: 0
  if parseHex(lookup.defaultText, value, start) == 0 or value > high(uint32).uint:
    return err[uint32](exactError("color property default is invalid",
      ErrorStage.objectStream, propertyKey = key,
      category = ErrorCategory.malformedData))
  ok(value.uint32)

proc stringProperty(item: WireObject; key: uint32): SplineyResult[string] =
  let lookup = item.propertyOrDefault(key)
  if not lookup.found:
    return err[string](exactError("missing generated string metadata",
      ErrorStage.objectStream, propertyKey = key,
      category = ErrorCategory.malformedData))
  if lookup.serialized:
    if lookup.value.kind notin {WireKind.stringValue, WireKind.bytesValue}:
      return err[string](exactError("string property has wrong wire value",
        ErrorStage.objectStream, propertyKey = key,
        category = ErrorCategory.malformedData))
    return ok(lookup.value.dataValue)
  var value = lookup.defaultText
  if value == "''" or value == "\"\"": value = ""
  ok(value)

template take(resultValue: untyped; expression: untyped;
    resultType: typedesc): untyped =
  block:
    let parsed = expression
    if not parsed.isOk:
      return err[resultType](parsed.error)
    resultValue = parsed.value

proc decodeIndices(data: string; objectId: uint32):
    SplineyResult[seq[uint16]] =
  var indices: seq[uint16]
  var offset = 0
  while offset < data.len:
    var value = 0'u64
    var complete = false
    for byteIndex in 0 .. 9:
      if offset >= data.len:
        return err[seq[uint16]](exactError("truncated mesh index varuint",
          ErrorStage.objectStream, objectId, 223,
          ErrorCategory.malformedData))
      let current = uint8(data[offset])
      inc offset
      if byteIndex == 9 and (current and 0xfe) != 0:
        return err[seq[uint16]](exactError("mesh index exceeds uint64",
          ErrorStage.objectStream, objectId, 223,
          ErrorCategory.malformedData))
      value = value or (uint64(current and 0x7f) shl (byteIndex * 7))
      if (current and 0x80) == 0:
        complete = true
        break
    if not complete or value > high(uint16).uint64:
      return err[seq[uint16]](exactError("mesh index exceeds uint16",
        ErrorStage.objectStream, objectId, 223,
        ErrorCategory.malformedData))
    indices.add(value.uint16)
  ok(indices)

proc importEmbeddedImages*(wire: WireFile):
    SplineyResult[seq[EmbeddedImageDefinition]] =
  var assets: seq[EmbeddedImageDefinition]
  var latest: EmbeddedImageDefinition
  for item in wire.objects:
    case item.typeKey
    of 105:
      var name: string
      var width, height: float32
      take(name, item.stringProperty(203), seq[EmbeddedImageDefinition])
      take(height, item.floatProperty(207), seq[EmbeddedImageDefinition])
      take(width, item.floatProperty(208), seq[EmbeddedImageDefinition])
      latest = EmbeddedImageDefinition(
        index: assets.len.uint32, name: name, width: width, height: height)
      assets.add(latest)
    of 106:
      if latest.isNil:
        return err[seq[EmbeddedImageDefinition]](exactError(
          "embedded bytes have no image asset", ErrorStage.referenceResolution))
      let bytes = item.stringProperty(212)
      if not bytes.isOk:
        return err[seq[EmbeddedImageDefinition]](bytes.error)
      latest.compressedBytes = bytes.value
    else:
      discard
  ok(assets)

proc newExactScene*(wire: WireFile; componentWireIndices: openArray[uint32];
    sharedImageAssets: seq[EmbeddedImageDefinition] = @[]):
    SplineyResult[ExactScene] =
  var imageAssets = sharedImageAssets
  if imageAssets.len == 0:
    let imported = importEmbeddedImages(wire)
    if not imported.isOk:
      return err[ExactScene](imported.error)
    imageAssets = imported.value
  let scene = ExactScene(imageAssets: imageAssets)

  for objectId, wireIndex in componentWireIndices:
    let item = wire.objects[wireIndex.int]
    let component = ExactComponent(
      objectId: objectId.uint32,
      typeKey: item.typeKey,
      scaleX: 1,
      scaleY: 1,
      opacity: 1,
      renderOpacity: 1,
      localTransform: IdentityMat2D,
      worldTransform: IdentityMat2D,
      bindTransform: IdentityMat2D,
      inverseBind: IdentityMat2D,
      strength: 1,
      targetId: MissingObjectId,
      assetId: MissingObjectId,
      boneId: MissingObjectId)
    if item.typeKey.inheritsFrom(10):
      take(component.parentId, item.uintProperty(5), ExactScene)
      take(component.name, item.stringProperty(4), ExactScene)
    if item.typeKey.inheritsFrom(38):
      take(component.rotation, item.floatProperty(15), ExactScene)
      take(component.scaleX, item.floatProperty(16), ExactScene)
      take(component.scaleY, item.floatProperty(17), ExactScene)
      take(component.opacity, item.floatProperty(18), ExactScene)
      if item.typeKey == 41:
        take(component.x, item.floatProperty(90), ExactScene)
        take(component.y, item.floatProperty(91), ExactScene)
      elif item.typeKey != 40:
        take(component.x, item.floatProperty(13), ExactScene)
        take(component.y, item.floatProperty(14), ExactScene)
      scene.transforms.add(component)
    case item.typeKey
    of 18:
      take(component.colorValue, item.colorProperty(37), ExactScene)
    of 20:
      take(component.fillRuleValue, item.uintProperty(40), ExactScene)
    of 40, 41:
      take(component.length, item.floatProperty(89), ExactScene)
    of 43:
      var xx, xy, yx, yy, tx, ty: float32
      take(xx, item.floatProperty(104), ExactScene)
      take(yx, item.floatProperty(105), ExactScene)
      take(xy, item.floatProperty(106), ExactScene)
      take(yy, item.floatProperty(107), ExactScene)
      take(tx, item.floatProperty(108), ExactScene)
      take(ty, item.floatProperty(109), ExactScene)
      component.bindTransform = mat2D(xx, xy, yx, yy, tx, ty)
      scene.skins.add(component)
    of 44:
      take(component.boneId, item.uintProperty(95, true), ExactScene)
      var xx, xy, yx, yy, tx, ty: float32
      take(xx, item.floatProperty(96), ExactScene)
      take(yx, item.floatProperty(97), ExactScene)
      take(xy, item.floatProperty(98), ExactScene)
      take(yy, item.floatProperty(99), ExactScene)
      take(tx, item.floatProperty(100), ExactScene)
      take(ty, item.floatProperty(101), ExactScene)
      component.inverseBind = mat2D(xx, xy, yx, yy, tx, ty).inverseOrIdentity
    of 45:
      take(component.weightValues, item.uintProperty(102), ExactScene)
      take(component.weightIndices, item.uintProperty(103), ExactScene)
    of 81:
      take(component.strength, item.floatProperty(172), ExactScene)
      take(component.targetId, item.uintProperty(173, true), ExactScene)
      var inverted: uint32
      take(inverted, item.uintProperty(174), ExactScene)
      component.invertDirection = inverted != 0
      take(component.parentBoneCount, item.uintProperty(175), ExactScene)
      scene.constraints.add(component)
    of 83:
      take(component.strength, item.floatProperty(172), ExactScene)
      take(component.targetId, item.uintProperty(173, true), ExactScene)
      take(component.sourceSpace, item.uintProperty(179), ExactScene)
      take(component.destSpace, item.uintProperty(180), ExactScene)
      take(component.originX, item.floatProperty(372), ExactScene)
      take(component.originY, item.floatProperty(373), ExactScene)
      scene.constraints.add(component)
    of 100:
      take(component.assetId, item.uintProperty(206, true), ExactScene)
      take(component.originX, item.floatProperty(380), ExactScene)
      take(component.originY, item.floatProperty(381), ExactScene)
      take(component.blendMode, item.uintProperty(23), ExactScene)
      if component.assetId >= scene.imageAssets.len.uint32:
        return err[ExactScene](exactError("image asset reference is invalid",
          ErrorStage.referenceResolution, component.objectId, 206))
      component.imageAsset = scene.imageAssets[component.assetId.int]
    of 109:
      let encoded = item.stringProperty(223)
      if not encoded.isOk: return err[ExactScene](encoded.error)
      let indices = decodeIndices(encoded.value, component.objectId)
      if not indices.isOk: return err[ExactScene](indices.error)
      component.triangleIndices = indices.value
      scene.meshes.add(component)
    of 111:
      take(component.vertexX, item.floatProperty(24), ExactScene)
      take(component.vertexY, item.floatProperty(25), ExactScene)
      take(component.u, item.floatProperty(215), ExactScene)
      take(component.v, item.floatProperty(216), ExactScene)
      component.renderTranslation = vec2(component.vertexX, component.vertexY)
    else:
      discard
    scene.components.add(component)

  for component in scene.components:
    if component.objectId != 0:
      if component.parentId >= scene.components.len.uint32:
        return err[ExactScene](exactError("component parent is invalid",
          ErrorStage.referenceResolution, component.objectId, 5))
      component.parent = scene.components[component.parentId.int]
      component.parent.children.add(component)
    case component.typeKey
    of 44:
      if component.parent.isNil or component.parent.typeKey != 43:
        return err[ExactScene](exactError("tendon parent is not a Skin",
          ErrorStage.referenceResolution, component.objectId, 5))
      if component.boneId >= scene.components.len.uint32 or
          scene.components[component.boneId.int].typeKey notin 40'u32 .. 41'u32:
        return err[ExactScene](exactError("tendon bone reference is invalid",
          ErrorStage.referenceResolution, component.objectId, 95))
      component.bone = scene.components[component.boneId.int]
      component.parent.tendons.add(component)
    of 45:
      if component.parent.isNil or component.parent.typeKey != 111:
        return err[ExactScene](exactError("weight parent is not a mesh vertex",
          ErrorStage.referenceResolution, component.objectId, 5))
      component.parent.weight = component
    of 43:
      if component.parent.isNil or component.parent.typeKey != 109:
        return err[ExactScene](exactError("Skin parent is not a Mesh",
          ErrorStage.referenceResolution, component.objectId, 5))
      component.parent.skin = component
    of 109:
      if component.parent.isNil or component.parent.typeKey != 100:
        return err[ExactScene](exactError("Mesh parent is not an Image",
          ErrorStage.referenceResolution, component.objectId, 5))
      component.parent.mesh = component
    of 111:
      if component.parent.isNil or component.parent.typeKey != 109:
        return err[ExactScene](exactError("mesh vertex parent is not a Mesh",
          ErrorStage.referenceResolution, component.objectId, 5))
      component.parent.vertices.add(component)
    of 81, 83:
      if component.parent.isNil or not component.parent.typeKey.inheritsFrom(38):
        return err[ExactScene](exactError("constraint parent is not transformable",
          ErrorStage.referenceResolution, component.objectId, 5))
      if component.targetId >= scene.components.len.uint32 or
          not scene.components[component.targetId.int].typeKey.inheritsFrom(38):
        return err[ExactScene](exactError("constraint target is invalid",
          ErrorStage.referenceResolution, component.objectId, 173))
      component.target = scene.components[component.targetId.int]
      component.parent.constraints.add(component)
    else:
      discard

  for component in scene.components:
    if component.typeKey == 20:
      for child in component.children:
        if child.typeKey == 18:
          scene.solidFill = component
          scene.fillPaintSource = child
          break

  for mesh in scene.meshes:
    for index in mesh.triangleIndices:
      if index.int >= mesh.vertices.len:
        return err[ExactScene](exactError("mesh index is out of range",
          ErrorStage.referenceResolution, mesh.objectId, 223,
          ErrorCategory.malformedData))
  for skin in scene.skins:
    skin.boneTransforms = newSeq[Mat2D](skin.tendons.len + 1)
    skin.boneTransforms[0] = IdentityMat2D
  ok(scene)

proc syncAnimated*(scene: ExactScene; registry: CorePropertyRegistry) =
  const animatedKeys = [13'u32, 14, 15, 16, 17, 18, 89, 90, 91, 172, 372, 373]
  for component in scene.components:
    let target = registry.resolveTarget(component.objectId)
    if target.isNil: continue
    for key in animatedKeys:
      let value = target.floatValue(key)
      if not value.isOk: continue
      case key
      of 13: component.x = value.value
      of 14: component.y = value.value
      of 15: component.rotation = value.value
      of 16: component.scaleX = value.value
      of 17: component.scaleY = value.value
      of 18: component.opacity = value.value
      of 89: component.length = value.value
      of 90: component.x = value.value
      of 91: component.y = value.value
      of 172: component.strength = value.value
      of 372: component.originX = value.value
      of 373: component.originY = value.value
      else: discard

proc parentWorld(component: ExactComponent): Mat2D =
  if not component.parent.isNil and component.parent.typeKey.inheritsFrom(38):
    component.parent.worldTransform
  else:
    IdentityMat2D

proc updateLocal(component: ExactComponent) =
  var x = component.x
  var y = component.y
  if component.typeKey == 40 and not component.parent.isNil:
    x = component.parent.length
    y = 0
  component.localTransform = rotationMat2D(component.rotation)
  component.localTransform.values[4] = x
  component.localTransform.values[5] = y
  component.localTransform.values[0] *= component.scaleX
  component.localTransform.values[1] *= component.scaleX
  component.localTransform.values[2] *= component.scaleY
  component.localTransform.values[3] *= component.scaleY

proc constrainRotation(component: ExactComponent;
    transformComponents: TransformComponents; rotation: float32) =
  var local = rotationMat2D(rotation)
  local.values[4] = transformComponents.x
  local.values[5] = transformComponents.y
  local.values[0] *= transformComponents.scaleX
  local.values[1] *= transformComponents.scaleX
  local.values[2] *= transformComponents.scaleY
  local.values[3] *= transformComponents.scaleY
  if transformComponents.skew != 0:
    local.values[2] = local.values[0] * transformComponents.skew + local.values[2]
    local.values[3] = local.values[1] * transformComponents.skew + local.values[3]
  component.localTransform = local
  component.worldTransform = component.parentWorld * local

type BoneChainLink = object
  bone: ExactComponent
  parentWorldInverse: Mat2D
  transformComponents: TransformComponents
  angle: float32

proc solveIk(constraint: ExactComponent) =
  if constraint.target.isNil: return
  var reverseBones = @[constraint.parent]
  var bone = constraint.parent
  var remaining = constraint.parentBoneCount
  while not bone.parent.isNil and bone.parent.typeKey in 40'u32 .. 41'u32 and
      remaining > 0:
    dec remaining
    bone = bone.parent
    reverseBones.add(bone)
  var chain = newSeq[BoneChainLink](reverseBones.len)
  for index in 0 ..< reverseBones.len:
    chain[index].bone = reverseBones[reverseBones.high - index]
    let parent = chain[index].bone.parentWorld
    chain[index].parentWorldInverse = parent.inverseOrIdentity
    chain[index].bone.localTransform =
      chain[index].parentWorldInverse * chain[index].bone.worldTransform
    chain[index].transformComponents = chain[index].bone.localTransform.decompose

  proc applyRotation(index: int; angle: float32) =
    chain[index].bone.constrainRotation(chain[index].transformComponents, angle)
    chain[index].angle = angle

  proc solveOne(index: int; target: Vec2D) =
    let link = chain[index]
    let origin = vec2(link.bone.worldTransform.values[4],
      link.bone.worldTransform.values[5])
    let localDirection = link.parentWorldInverse.transformDirection(target - origin)
    applyRotation(index, arctan2(localDirection.y, localDirection.x))

  proc solveTwo(firstIndex, tipIndex: int; target: Vec2D) =
    let firstBone = chain[firstIndex].bone
    let tipBone = chain[tipIndex].bone
    let childIndex = firstIndex + 1
    let inverseWorld = chain[firstIndex].parentWorldInverse
    var pointA = inverseWorld * vec2(firstBone.worldTransform.values[4],
      firstBone.worldTransform.values[5])
    var pointC = inverseWorld * vec2(chain[childIndex].bone.worldTransform.values[4],
      chain[childIndex].bone.worldTransform.values[5])
    var pointB = inverseWorld * (tipBone.worldTransform * vec2(tipBone.length, 0))
    let pointTarget = inverseWorld * target
    let a = (pointB - pointC).length
    let b = (pointC - pointA).length
    let c = (pointTarget - pointA).length
    if a == 0 or b == 0 or c == 0: return
    let angleA = arccos(clamp((-a*a + b*b + c*c) / (2*b*c), -1'f32, 1'f32))
    let angleC = arccos(clamp((a*a + b*b - c*c) / (2*a*b), -1'f32, 1'f32))
    let cv = pointTarget - pointA
    var rotation1, rotation2: float32
    if tipBone.parent != firstBone:
      let secondChildIndex = firstIndex + 2
      let currentC = vec2(chain[childIndex].bone.worldTransform.values[4],
        chain[childIndex].bone.worldTransform.values[5])
      let currentB = tipBone.worldTransform * vec2(tipBone.length, 0)
      let local = chain[secondChildIndex].parentWorldInverse.transformDirection(
        currentB - currentC)
      let correction = -arctan2(local.y, local.x)
      if constraint.invertDirection:
        rotation1 = arctan2(cv.y, cv.x) - angleA
        rotation2 = -angleC + PI.float32 + correction
      else:
        rotation1 = angleA + arctan2(cv.y, cv.x)
        rotation2 = angleC - PI.float32 + correction
    elif constraint.invertDirection:
      rotation1 = arctan2(cv.y, cv.x) - angleA
      rotation2 = -angleC + PI.float32
    else:
      rotation1 = angleA + arctan2(cv.y, cv.x)
      rotation2 = angleC - PI.float32
    applyRotation(firstIndex, rotation1)
    applyRotation(childIndex, rotation2)
    if childIndex != tipIndex:
      tipBone.worldTransform = tipBone.parentWorld * tipBone.localTransform
    chain[firstIndex].angle = rotation1
    chain[childIndex].angle = rotation2

  let target = vec2(constraint.target.worldTransform.values[4],
    constraint.target.worldTransform.values[5])
  case chain.len
  of 1: solveOne(0, target)
  of 2: solveTwo(0, 1, target)
  else:
    let tip = chain.high
    for index in 0 ..< tip:
      solveTwo(index, tip, target)
      for childIndex in index + 1 ..< tip:
        chain[childIndex].parentWorldInverse =
          chain[childIndex].bone.parentWorld.inverseOrIdentity

  if constraint.strength != 1:
    for index in 0 .. chain.high:
      let fromAngle = floorMod(chain[index].transformComponents.rotation,
        PI.float32 * 2)
      let toAngle = floorMod(chain[index].angle, PI.float32 * 2)
      var difference = toAngle - fromAngle
      if difference > PI.float32: difference -= PI.float32 * 2
      elif difference < -PI.float32: difference += PI.float32 * 2
      applyRotation(index, fromAngle + difference * constraint.strength)

proc solveTransformConstraint(constraint: ExactComponent) =
  if constraint.target.isNil: return
  let component = constraint.parent
  var targetTransform = constraint.target.worldTransform
  if constraint.sourceSpace == 1:
    targetTransform = constraint.target.parentWorld.inverseOrIdentity * targetTransform
  if constraint.destSpace == 1:
    targetTransform = component.parentWorld * targetTransform
  var fromComponents = component.worldTransform.decompose
  var toComponents = targetTransform.decompose
  let angleA = floorMod(fromComponents.rotation, PI.float32 * 2)
  let angleB = floorMod(toComponents.rotation, PI.float32 * 2)
  var difference = angleB - angleA
  if difference > PI.float32: difference -= PI.float32 * 2
  elif difference < -PI.float32: difference += PI.float32 * 2
  let strength = constraint.strength
  let inverseStrength = 1 - strength
  toComponents.rotation = angleA + difference * strength
  toComponents.x = fromComponents.x * inverseStrength + toComponents.x * strength
  toComponents.y = fromComponents.y * inverseStrength + toComponents.y * strength
  toComponents.scaleX = fromComponents.scaleX * inverseStrength +
    toComponents.scaleX * strength
  toComponents.scaleY = fromComponents.scaleY * inverseStrength +
    toComponents.scaleY * strength
  toComponents.skew = fromComponents.skew * inverseStrength +
    toComponents.skew * strength
  component.worldTransform = toComponents.compose

proc settle*(scene: ExactScene): SplineyStatus =
  if scene.isNil:
    return errStatus(exactError("nil exact scene", ErrorStage.frameAdvance))
  var state = newSeq[uint8](scene.components.len)
  proc solve(component: ExactComponent): bool =
    if not component.typeKey.inheritsFrom(38): return true
    case state[component.objectId.int]
    of 1: return false
    of 2: return true
    else: discard
    state[component.objectId.int] = 1
    if not component.parent.isNil and component.parent.typeKey.inheritsFrom(38):
      if not solve(component.parent): return false
    for constraint in component.constraints:
      if not constraint.target.isNil and not solve(constraint.target): return false
    component.updateLocal()
    component.worldTransform = component.parentWorld * component.localTransform
    component.renderOpacity = component.opacity *
      (if not component.parent.isNil and component.parent.typeKey.inheritsFrom(38):
        component.parent.renderOpacity else: 1)
    for constraint in component.constraints:
      if constraint.typeKey == 81: solveIk(constraint)
      elif constraint.typeKey == 83: solveTransformConstraint(constraint)
    state[component.objectId.int] = 2
    true
  for component in scene.transforms:
    if not solve(component):
      return errStatus(exactError("transform dependency cycle",
        ErrorStage.frameAdvance, component.objectId))

  for skin in scene.skins:
    for index, tendon in skin.tendons:
      skin.boneTransforms[index + 1] = tendon.bone.worldTransform * tendon.inverseBind
  for mesh in scene.meshes:
    for vertex in mesh.vertices:
      if mesh.skin.isNil or vertex.weight.isNil:
        vertex.renderTranslation = vec2(vertex.vertexX, vertex.vertexY)
        continue
      var blended = mat2D(0, 0, 0, 0, 0, 0)
      for slot in 0 .. 3:
        let weight = (vertex.weight.weightValues shr (slot * 8)) and 0xff
        if weight == 0: continue
        let boneIndex = (vertex.weight.weightIndices shr (slot * 8)) and 0xff
        if boneIndex >= mesh.skin.boneTransforms.len.uint32:
          return errStatus(exactError("weight bone index is invalid",
            ErrorStage.frameAdvance, vertex.weight.objectId, 103))
        let factor = weight.float32 / 255
        for matrixIndex in 0 .. 5:
          blended.values[matrixIndex] +=
            mesh.skin.boneTransforms[boneIndex.int].values[matrixIndex] * factor
      vertex.renderTranslation = blended *
        (mesh.skin.bindTransform * vec2(vertex.vertexX, vertex.vertexY))
  okStatus()

proc drawError(message: string; objectId = MissingObjectId;
    assetId: int64 = -1): SplineyError =
  SplineyError(
    category: ErrorCategory.render,
    stage: ErrorStage.drawSubmission,
    message: message,
    context: ErrorContext(
      label: if objectId == MissingObjectId: "" else: $objectId,
      objectTypeKey: -1,
      propertyKey: -1,
      assetId: assetId,
      animationIndex: -1))

proc ensureFillResources(scene: ExactScene; factory: Factory;
    artboardBounds: AABB): SplineyStatus =
  if scene.solidFill.isNil: return okStatus()
  if not scene.renderFactory.isNil and scene.renderFactory != factory:
    return errStatus(drawError(
      "scene draw resources belong to a different factory"))
  if not scene.renderFillPath.isNil: return okStatus()
  var raw: RawPath
  raw.moveTo(vec2(artboardBounds.minX, artboardBounds.minY))
  raw.lineTo(vec2(artboardBounds.maxX, artboardBounds.minY))
  raw.lineTo(vec2(artboardBounds.maxX, artboardBounds.maxY))
  raw.lineTo(vec2(artboardBounds.minX, artboardBounds.maxY))
  raw.close()
  if scene.solidFill.fillRuleValue > ord(high(FillRule)).uint32:
    return errStatus(drawError("unsupported exact fill rule",
      scene.solidFill.objectId))
  scene.renderFillPath = factory.makeRenderPath(raw,
    FillRule(scene.solidFill.fillRuleValue))
  scene.renderFillPaint = factory.makeRenderPaint()
  if scene.renderFillPath.isNil or scene.renderFillPaint.isNil:
    scene.renderFillPath = nil
    scene.renderFillPaint = nil
    return errStatus(drawError("factory failed to create fill resources",
      scene.solidFill.objectId))
  scene.renderFillPaint.style(RenderPaintStyle.fill)
  scene.renderFillPaint.color(scene.fillPaintSource.colorValue)
  scene.renderFactory = factory
  okStatus()

proc ensureMeshBuffers(mesh: ExactComponent; factory: Factory): SplineyStatus =
  template discardBuffers() =
    mesh.renderVertexBuffer = nil
    mesh.renderUvBuffer = nil
    mesh.renderIndexBuffer = nil
    mesh.staticBuffersInitialized = false

  let vertexByteCount = mesh.vertices.len * 2 * sizeof(float32)
  let indexByteCount = mesh.triangleIndices.len * sizeof(uint16)
  if mesh.renderVertexBuffer.isNil:
    mesh.renderVertexBuffer = factory.makeRenderBuffer(
      RenderBufferType.vertex, {}, vertexByteCount)
    mesh.renderUvBuffer = factory.makeRenderBuffer(
      RenderBufferType.vertex,
      {RenderBufferFlag.mappedOnceAtInitialization}, vertexByteCount)
    mesh.renderIndexBuffer = factory.makeRenderBuffer(
      RenderBufferType.index,
      {RenderBufferFlag.mappedOnceAtInitialization}, indexByteCount)
    if mesh.renderVertexBuffer.isNil or mesh.renderUvBuffer.isNil or
        mesh.renderIndexBuffer.isNil:
      discardBuffers()
      return errStatus(drawError("factory failed to create mesh buffers",
        mesh.objectId))

  if not mesh.staticBuffersInitialized:
    let uvDestination = cast[ptr UncheckedArray[float32]](
      mesh.renderUvBuffer.map())
    if vertexByteCount > 0 and uvDestination.isNil:
      mesh.renderUvBuffer.unmap()
      discardBuffers()
      return errStatus(drawError("mesh UV buffer mapping failed",
        mesh.objectId))
    for index, vertex in mesh.vertices:
      uvDestination[index * 2] = vertex.u
      uvDestination[index * 2 + 1] = vertex.v
    mesh.renderUvBuffer.unmap()

    let indexDestination = cast[ptr UncheckedArray[uint16]](
      mesh.renderIndexBuffer.map())
    if indexByteCount > 0 and indexDestination.isNil:
      mesh.renderIndexBuffer.unmap()
      discardBuffers()
      return errStatus(drawError("mesh index buffer mapping failed",
        mesh.objectId))
    for index, value in mesh.triangleIndices:
      indexDestination[index] = value
    mesh.renderIndexBuffer.unmap()
    mesh.staticBuffersInitialized = true

  let vertexDestination = cast[ptr UncheckedArray[float32]](
    mesh.renderVertexBuffer.map())
  if vertexByteCount > 0 and vertexDestination.isNil:
    mesh.renderVertexBuffer.unmap()
    discardBuffers()
    return errStatus(drawError("mesh vertex buffer mapping failed",
      mesh.objectId))
  for index, vertex in mesh.vertices:
    vertexDestination[index * 2] = vertex.renderTranslation.x
    vertexDestination[index * 2 + 1] = vertex.renderTranslation.y
  mesh.renderVertexBuffer.unmap()
  okStatus()

proc decodeBlendMode(value: uint32; decoded: var BlendMode): bool =
  case value
  of 3: decoded = BlendMode.srcOver
  of 14: decoded = BlendMode.screen
  of 15: decoded = BlendMode.overlay
  of 16: decoded = BlendMode.darken
  of 17: decoded = BlendMode.lighten
  of 18: decoded = BlendMode.colorDodge
  of 19: decoded = BlendMode.colorBurn
  of 20: decoded = BlendMode.hardLight
  of 21: decoded = BlendMode.softLight
  of 22: decoded = BlendMode.difference
  of 23: decoded = BlendMode.exclusion
  of 24: decoded = BlendMode.multiply
  of 25: decoded = BlendMode.hue
  of 26: decoded = BlendMode.saturation
  of 27: decoded = BlendMode.color
  of 28: decoded = BlendMode.luminosity
  else: return false
  true

proc emitDrawCommands*(scene: ExactScene; factory: Factory;
    renderer: Renderer; images: openArray[RenderImage]; artboardBounds: AABB;
    presentation: Mat2D): SplineyStatus =
  ## Emits the exact asset's audited solid artboard fill and image drawables.
  ## Images are traversed in reverse component order, matching Rive's stable
  ## back-to-front draw order.
  if scene.isNil or factory.isNil or renderer.isNil:
    return errStatus(drawError("nil exact draw dependency"))
  if not scene.renderFactory.isNil and scene.renderFactory != factory:
    return errStatus(drawError(
      "scene draw resources belong to a different factory"))
  let fillReady = scene.ensureFillResources(factory, artboardBounds)
  if not fillReady.isOk: return fillReady
  if scene.renderFactory.isNil: scene.renderFactory = factory

  renderer.save()
  renderer.transform(presentation)
  if not scene.renderFillPath.isNil:
    renderer.drawPath(scene.renderFillPath, scene.renderFillPaint)

  for componentIndex in countdown(scene.components.high, 0):
    let imageComponent = scene.components[componentIndex]
    if imageComponent.typeKey != 100 or imageComponent.renderOpacity <= 0:
      continue
    if imageComponent.assetId >= images.len.uint32 or
        images[imageComponent.assetId.int].isNil:
      renderer.restore()
      return errStatus(drawError("prepared image reference is invalid",
        imageComponent.objectId, imageComponent.assetId.int64))
    var blendMode: BlendMode
    if not imageComponent.blendMode.decodeBlendMode(blendMode):
      renderer.restore()
      return errStatus(drawError("unsupported exact image blend mode",
        imageComponent.objectId, imageComponent.assetId.int64))
    let image = images[imageComponent.assetId.int]
    renderer.save()
    if imageComponent.mesh.isNil:
      renderer.transform(imageComponent.worldTransform * translationMat2D(
        -image.width.float32 * imageComponent.originX,
        -image.height.float32 * imageComponent.originY))
      renderer.drawImage(image, LinearClampSampler, blendMode,
        imageComponent.renderOpacity)
    else:
      let mesh = imageComponent.mesh
      let buffersReady = mesh.ensureMeshBuffers(factory)
      if not buffersReady.isOk:
        renderer.restore()
        renderer.restore()
        return buffersReady
      if mesh.skin.isNil:
        renderer.transform(imageComponent.worldTransform)
      renderer.drawImageMesh(image, LinearClampSampler,
        mesh.renderVertexBuffer, mesh.renderUvBuffer, mesh.renderIndexBuffer,
        mesh.vertices.len.uint32, mesh.triangleIndices.len.uint32,
        blendMode, imageComponent.renderOpacity)
    renderer.restore()
  renderer.restore()
  okStatus()
