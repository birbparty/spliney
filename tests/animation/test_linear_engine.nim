import std/unittest

import spliney/animation/engine/linear
import spliney/animation/interp/easing
import spliney/animation/keyed/runtime
import spliney/core/transform/node

proc close(left, right: float32): bool = abs(left - right) < 0.00001

proc definition(loopMode = LoopMode.oneShot; speed = 1'f32;
    workStart = 0'u32; workEnd = 10'u32; workArea = false):
    LinearAnimationDefinition =
  LinearAnimationDefinition(
    objectId: 20,
    name: "test",
    fps: 10,
    durationFrames: 10,
    speed: speed,
    loopMode: loopMode,
    workStart: workStart,
    workEnd: workEnd,
    enableWorkArea: workArea,
    keyed: KeyedAnimationDefinition(objectId: 20))

proc instance(definition: LinearAnimationDefinition): LinearAnimationInstance =
  newLinearAnimationInstance(definition, newCorePropertyRegistry()).value

suite "linear animation engine":
  test "grounded loop enum values and one-shot spill behavior":
    check LoopMode.oneShot.uint32 == 0
    check LoopMode.loop.uint32 == 1
    check LoopMode.pingPong.uint32 == 2
    let playback = instance(definition())
    let advanced = playback.advance(1.25)
    require advanced.isOk
    check not advanced.value
    check playback.time == 1
    check playback.spilledTime.close(0.25)
    check playback.didLoop
    check playback.advance(0).value == false
    check not playback.didLoop

  test "loop wraps large forward and reverse deltas":
    let forward = instance(definition(LoopMode.loop))
    require forward.advance(2.25).isOk
    check forward.time.close(0.25)
    check forward.spilledTime.close(0.25)

    let exactEnd = instance(definition(LoopMode.loop))
    require exactEnd.advance(1).isOk
    check exactEnd.time == 0
    check exactEnd.didLoop

    let reverse = instance(definition(LoopMode.loop))
    reverse.setDirection(-1)
    require reverse.seek(0.5).isOk
    reverse.setDirection(-1)
    require reverse.advance(0.75).isOk
    check reverse.time.close(0.75)
    check reverse.didLoop

  test "ping-pong reflects across every crossed boundary":
    let playback = instance(definition(LoopMode.pingPong))
    require playback.advance(2.25).isOk
    check playback.time.close(0.25)
    check playback.direction == 1
    check playback.didLoop

    require playback.seek(0).isOk
    playback.setDirection(-1)
    require playback.advance(0.1).isOk
    check playback.time.close(0.1)
    check playback.direction == 1

  test "work area and negative authored speed choose authored endpoints":
    let forward = instance(definition(LoopMode.oneShot, workStart = 2,
      workEnd = 8, workArea = true))
    check forward.time.close(0.2)
    check forward.definition.startSeconds.close(0.2)
    check forward.definition.endSeconds.close(0.8)

    let reverse = instance(definition(LoopMode.oneShot, speed = -2,
      workStart = 2, workEnd = 8, workArea = true))
    check reverse.time.close(0.8)
    require reverse.advance(0.1).isOk
    check reverse.time.close(0.6)

  test "advance and apply mutates only its registered scene":
    let nodeDefinition = NodeDefinition(
      objectId: 7, typeKey: 2, scaleX: 1, scaleY: 1, opacity: 1)
    let firstNode = newNodeInstance(nodeDefinition)
    let secondNode = newNodeInstance(nodeDefinition)
    let firstRegistry = newCorePropertyRegistry()
    let secondRegistry = newCorePropertyRegistry()
    let firstTarget = newCorePropertyTarget(7, 2)
    let secondTarget = newCorePropertyTarget(7, 2)
    require firstTarget.bindNodeProperties(firstNode).isOk
    require secondTarget.bindNodeProperties(secondNode).isOk
    require firstRegistry.registerTarget(firstTarget).isOk
    require secondRegistry.registerTarget(secondTarget).isOk
    let keyed = KeyedAnimationDefinition(objectId: 20, keyedObjects: @[
      KeyedObjectDefinition(objectId: 7, properties: @[
        KeyedPropertyDefinition(propertyKey: 13, frames: @[
          KeyFrameDoubleDefinition(frame: 0,
            interpolation: InterpolationKind.interpolate,
            interpolatorId: MissingObjectId, value: 0),
          KeyFrameDoubleDefinition(frame: 10,
            interpolation: InterpolationKind.interpolate,
            interpolatorId: MissingObjectId, value: 10)])])])
    let animation = definition(LoopMode.loop)
    animation.keyed = keyed
    let first = newLinearAnimationInstance(animation, firstRegistry).value
    let second = newLinearAnimationInstance(animation, secondRegistry).value
    require first.advanceAndApply(0.25).isOk
    require second.advanceAndApply(0.75).isOk
    check firstNode.x.close(2.5)
    check secondNode.x.close(7.5)
    check nodeDefinition.x == 0

  test "invalid ranges and non-finite host values fail structurally":
    let invalid = definition(LoopMode.loop, workStart = 5,
      workEnd = 5, workArea = true)
    check not invalid.validate.isOk
    let playback = instance(definition())
    check not playback.advance(0'f32 / 0'f32).isOk
