import std/unittest

import spliney/animation/interp/easing

proc close(a, b: float32; tolerance = 0.00001'f32): bool = abs(a - b) <= tolerance

suite "Rive keyframe interpolation":
  test "grounded kinds distinguish hold from interpolation":
    check InterpolationKind.hold.ord == 0
    check InterpolationKind.interpolate.ord == 1
    check interpolate(10, 20, 0.75, InterpolationKind.hold) == 10
    check interpolate(10, 20, 0.75) == 17.5

  test "cubic solver matches standard reference curves":
    let linear = cubicBezier(0, 0, 1, 1)
    for factor in [0'f32, 0.1, 0.25, 0.5, 0.9, 1]:
      check linear.transform(factor).close(factor)
    let ease = cubicBezier(0.25, 0.1, 0.25, 1)
    check ease.transform(0) == 0
    check ease.transform(1) == 1
    check ease.transform(0.5).close(0.8024034, 0.00001)
    check interpolate(100, 200, 0.5, curve = unsafeAddr ease).close(180.24034)

  test "flat slopes use the bounded subdivision path":
    let curve = cubicBezier(0, 0.5, 0, 0.5)
    let value = curve.transform(0.0001)
    check value > 0
    check value < 1

  test "invalid x controls fail before solver construction":
    expect ValueError: discard cubicBezier(-0.1, 0, 1, 1)
    expect ValueError: discard cubicBezier(0, 0, 1.1, 1)
    expect ValueError: discard cubicBezier(NaN.float32, 0, 1, 1)
