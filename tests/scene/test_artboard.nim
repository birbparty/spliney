import std/unittest

import spliney/animation/engine/linear
import spliney/animation/interp/easing
import spliney/animation/keyed/runtime
import spliney/io/loader
import spliney/scene/artboard

proc close(left, right: float32): bool = abs(left - right) < 0.00001

proc animation(objectId: uint32; startValue, endValue: float32):
    LinearAnimationDefinition =
  LinearAnimationDefinition(
    objectId: objectId,
    name: "animation " & $objectId,
    fps: 10,
    durationFrames: 10,
    speed: 1,
    loopMode: LoopMode.loop,
    keyed: KeyedAnimationDefinition(objectId: objectId, keyedObjects: @[
      KeyedObjectDefinition(objectId: 1, properties: @[
        KeyedPropertyDefinition(propertyKey: 13, frames: @[
          KeyFrameDoubleDefinition(frame: 0,
            interpolation: InterpolationKind.interpolate,
            interpolatorId: MissingObjectId, value: startValue),
          KeyFrameDoubleDefinition(frame: 10,
            interpolation: InterpolationKind.interpolate,
            interpolatorId: MissingObjectId, value: endValue)])])]))

proc fixture(): ArtboardDefinition =
  let wire = WireFile(objects: @[
    WireObject(typeKey: 1, knownType: true),
    WireObject(typeKey: 2, knownType: true)])
  ArtboardDefinition(
    objectIndex: 0,
    componentCount: 2,
    componentWireIndices: @[0'u32, 1],
    name: "test",
    width: 100,
    height: 100,
    wire: wire,
    animations: @[animation(2, 0, 10), animation(3, 100, 200)])

suite "artboard definition and instance":
  test "instances settle and advance independently from one definition":
    let definition = fixture()
    let first = definition.cloneArtboard(0).value
    let second = definition.cloneArtboard(0).value
    require first.initialSettle().isOk
    require second.initialSettle().isOk
    check first.animatedFloat(1, 13).value == 0
    let firstAdvance = first.advanceAndApply(0.1)
    if not firstAdvance.isOk: checkpoint firstAdvance.error.message
    require firstAdvance.isOk
    require second.advanceAndApply(0.05).isOk
    check first.animatedFloat(1, 13).value.close(1)
    check second.animatedFloat(1, 13).value.close(0.5)
    check definition.wire.objects[1].propertyOrDefault(13).defaultText == "0"

  test "canonical frame operation requires initial settle and bounded delta":
    let instance = fixture().cloneArtboard(0).value
    check not instance.advanceAndApply(0.1).isOk
    require instance.initialSettle().isOk
    check not instance.advanceAndApply(0).isOk
    check not instance.advanceAndApply(0.10001).isOk
    check not instance.advanceAndApply(0'f32 / 0'f32).isOk

  test "replacement commits only a settled candidate":
    for fault in [SceneBuildFault.clone, SceneBuildFault.startApply,
        SceneBuildFault.settle]:
      var subject = fixture().cloneArtboard(0).value
      let control = fixture().cloneArtboard(0).value
      require subject.initialSettle().isOk
      require control.initialSettle().isOk
      require subject.advanceAndApply(0.1).isOk
      require control.advanceAndApply(0.1).isOk
      require subject.poisonAnimatedValues(-999).isOk
      require control.poisonAnimatedValues(-999).isOk

      let previous = subject
      let failed = subject.replaceAnimation(1, fault)
      check not failed.isOk
      check subject == previous
      require subject.advanceAndApply(0.1).isOk
      require control.advanceAndApply(0.1).isOk
      check subject.animation.time == control.animation.time
      check subject.animatedFloat(1, 13).value ==
        control.animatedFloat(1, 13).value

    var successful = fixture().cloneArtboard(0).value
    require successful.initialSettle().isOk
    let old = successful
    require successful.replaceAnimation(1).isOk
    check successful != old
    check successful.animationIndex == 1
    check successful.animatedFloat(1, 13).value == 100
