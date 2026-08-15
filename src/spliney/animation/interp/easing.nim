## Headless keyframe interpolation grounded against Rive's cubic solver.

import std/math

type
  InterpolationKind* {.pure.} = enum
    hold = 0
    interpolate = 1

  CubicBezier* = object
    x1*, y1*, x2*, y2*: float32
    samples: array[11, float32]

const
  SampleStep = 0.1'f32
  NewtonIterations = 4
  NewtonMinSlope = 0.001'f32
  SubdivisionPrecision = 0.0000001'f32
  SubdivisionMaxIterations = 10

proc calcBezier*(t, a1, a2: float32): float32 =
  (((1'f32 - 3 * a2 + 3 * a1) * t + (3 * a2 - 6 * a1)) * t +
    3 * a1) * t

proc slope(t, a1, a2: float32): float32 =
  3 * (1'f32 - 3 * a2 + 3 * a1) * t * t +
    2 * (3 * a2 - 6 * a1) * t + 3 * a1

proc cubicBezier*(x1, y1, x2, y2: float32): CubicBezier =
  if classify(x1) in {fcNan, fcInf, fcNegInf} or
      classify(x2) in {fcNan, fcInf, fcNegInf} or x1 < 0 or x1 > 1 or
      x2 < 0 or x2 > 1:
    raise newException(ValueError,
      "cubic Bezier x control points must be finite in [0, 1]")
  result = CubicBezier(x1: x1, y1: y1, x2: x2, y2: y2)
  for index in 0 .. result.samples.high:
    result.samples[index] = calcBezier(index.float32 * SampleStep, x1, x2)

proc parameterAt(curve: CubicBezier; x: float32): float32 =
  if x <= 0: return 0
  if x >= 1: return 1
  var intervalStart = 0'f32
  var currentSample = 1
  while currentSample != curve.samples.high and
      curve.samples[currentSample] <= x:
    inc currentSample
    intervalStart += SampleStep
  dec currentSample
  let denominator = curve.samples[currentSample + 1] -
    curve.samples[currentSample]
  var guess = if denominator == 0: intervalStart else:
    intervalStart + (x - curve.samples[currentSample]) /
      denominator * SampleStep
  let initialSlope = slope(guess, curve.x1, curve.x2)
  if initialSlope >= NewtonMinSlope:
    for _ in 0 ..< NewtonIterations:
      let currentSlope = slope(guess, curve.x1, curve.x2)
      if currentSlope == 0: return guess
      guess -= (calcBezier(guess, curve.x1, curve.x2) - x) / currentSlope
    return guess
  if initialSlope == 0: return guess

  var upper = intervalStart + SampleStep
  var currentX = 0'f32
  var iteration = 0
  while true:
    guess = intervalStart + (upper - intervalStart) * 0.5
    currentX = calcBezier(guess, curve.x1, curve.x2) - x
    if currentX > 0: upper = guess else: intervalStart = guess
    inc iteration
    if abs(currentX) <= SubdivisionPrecision or
        iteration >= SubdivisionMaxIterations:
      break
  guess

proc transform*(curve: CubicBezier; factor: float32): float32 =
  if factor <= 0: return 0
  if factor >= 1: return 1
  calcBezier(curve.parameterAt(factor), curve.y1, curve.y2)

proc interpolationFactor*(kind: InterpolationKind; factor: float32;
    curve: ptr CubicBezier = nil): float32 =
  case kind
  of InterpolationKind.hold: 0
  of InterpolationKind.interpolate:
    if curve.isNil: factor else: curve[].transform(factor)

proc interpolate*(fromValue, toValue, factor: float32;
    kind = InterpolationKind.interpolate; curve: ptr CubicBezier = nil): float32 =
  let adjusted = interpolationFactor(kind, factor, curve)
  fromValue + (toValue - fromValue) * adjusted
