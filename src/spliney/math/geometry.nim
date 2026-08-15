## Allocation-free renderer-neutral 2D geometry matching Rive's conventions.

import std/math

type
  Vec2D* = object
    x*, y*: float32

  Mat2D* = object
    ## [xx, xy, yx, yy, tx, ty] in Rive's storage naming. Point mapping is
    ## (m0*x + m2*y + m4, m1*x + m3*y + m5).
    values*: array[6, float32]

  AABB* = object
    minX*, minY*, maxX*, maxY*: float32

  TransformComponents* = object
    x*, y*: float32
    scaleX*, scaleY*: float32
    rotation*: float32
    skew*: float32

proc vec2*(x, y: SomeNumber): Vec2D = Vec2D(x: x.float32, y: y.float32)
proc mat2D*(xx, xy, yx, yy, tx, ty: SomeNumber): Mat2D =
  Mat2D(values: [xx.float32, xy.float32, yx.float32, yy.float32,
    tx.float32, ty.float32])
proc aabb*(minX, minY, maxX, maxY: SomeNumber): AABB =
  AABB(minX: minX.float32, minY: minY.float32,
    maxX: maxX.float32, maxY: maxY.float32)

const IdentityMat2D* = Mat2D(values: [1'f32, 0, 0, 1, 0, 0])

proc `+`*(a, b: Vec2D): Vec2D = vec2(a.x + b.x, a.y + b.y)
proc `-`*(a, b: Vec2D): Vec2D = vec2(a.x - b.x, a.y - b.y)
proc `-`*(value: Vec2D): Vec2D = vec2(-value.x, -value.y)
proc `*`*(value: Vec2D; scalar: SomeNumber): Vec2D =
  vec2(value.x * scalar.float32, value.y * scalar.float32)
proc `*`*(scalar: SomeNumber; value: Vec2D): Vec2D = value * scalar
proc `/`*(value: Vec2D; scalar: SomeNumber): Vec2D =
  vec2(value.x / scalar.float32, value.y / scalar.float32)
proc dot*(a, b: Vec2D): float32 = a.x * b.x + a.y * b.y
proc cross*(a, b: Vec2D): float32 = a.x * b.y - a.y * b.x
proc lengthSquared*(value: Vec2D): float32 = value.dot(value)
proc length*(value: Vec2D): float32 = sqrt(value.lengthSquared)
proc normalized*(value: Vec2D): Vec2D =
  let magnitude = value.length
  if magnitude > 0: value / magnitude else: value
proc lerp*(a, b: Vec2D; t: float32): Vec2D = a + (b - a) * t
proc distanceSquared*(a, b: Vec2D): float32 = (a - b).lengthSquared
proc distance*(a, b: Vec2D): float32 = (a - b).length

proc translationMat2D*(x, y: SomeNumber): Mat2D =
  mat2D(1'f32, 0'f32, 0'f32, 1'f32, x.float32, y.float32)
proc scaleMat2D*(x, y: SomeNumber): Mat2D =
  mat2D(x.float32, 0'f32, 0'f32, y.float32, 0'f32, 0'f32)
proc rotationMat2D*(radians: float32): Mat2D =
  if radians == 0: return IdentityMat2D
  let sine = sin(radians)
  let cosine = cos(radians)
  mat2D(cosine, sine, -sine, cosine, 0'f32, 0'f32)

proc `*`*(a, b: Mat2D): Mat2D =
  let av = a.values
  let bv = b.values
  mat2D(
    av[0] * bv[0] + av[2] * bv[1],
    av[1] * bv[0] + av[3] * bv[1],
    av[0] * bv[2] + av[2] * bv[3],
    av[1] * bv[2] + av[3] * bv[3],
    av[0] * bv[4] + av[2] * bv[5] + av[4],
    av[1] * bv[4] + av[3] * bv[5] + av[5])

proc `*`*(matrix: Mat2D; point: Vec2D): Vec2D =
  vec2(
    matrix.values[0] * point.x + matrix.values[2] * point.y + matrix.values[4],
    matrix.values[1] * point.x + matrix.values[3] * point.y + matrix.values[5])

proc transformDirection*(matrix: Mat2D; direction: Vec2D): Vec2D =
  vec2(
    matrix.values[0] * direction.x + matrix.values[2] * direction.y,
    matrix.values[1] * direction.x + matrix.values[3] * direction.y)

proc determinant*(matrix: Mat2D): float32 =
  matrix.values[0] * matrix.values[3] -
    matrix.values[2] * matrix.values[1]

proc finite(value: float32): bool =
  classify(value) notin {fcNan, fcInf, fcNegInf}

proc inverse*(matrix: Mat2D; destination: var Mat2D): bool =
  let determinant = matrix.determinant
  if not determinant.finite or abs(determinant) <= 1e-12'f32: return false
  let inverseDeterminant = 1'f32 / determinant
  let candidate = mat2D(
    matrix.values[3] * inverseDeterminant,
    -matrix.values[1] * inverseDeterminant,
    -matrix.values[2] * inverseDeterminant,
    matrix.values[0] * inverseDeterminant,
    (matrix.values[2] * matrix.values[5] -
      matrix.values[3] * matrix.values[4]) * inverseDeterminant,
    (matrix.values[1] * matrix.values[4] -
      matrix.values[0] * matrix.values[5]) * inverseDeterminant)
  for value in candidate.values:
    if not value.finite: return false
  destination = candidate
  true

proc inverseOrIdentity*(matrix: Mat2D): Mat2D =
  result = IdentityMat2D
  discard matrix.inverse(result)

proc decompose*(matrix: Mat2D): TransformComponents =
  let m0 = matrix.values[0]
  let m1 = matrix.values[1]
  let m2 = matrix.values[2]
  let m3 = matrix.values[3]
  let denominator = m0 * m0 + m1 * m1
  let scaleX = sqrt(denominator)
  TransformComponents(
    x: matrix.values[4],
    y: matrix.values[5],
    scaleX: scaleX,
    scaleY: if scaleX == 0: 0 else: (m0 * m3 - m2 * m1) / scaleX,
    rotation: arctan2(m1, m0),
    skew: arctan2(m0 * m2 + m1 * m3, denominator))

proc compose*(components: TransformComponents): Mat2D =
  result = rotationMat2D(components.rotation)
  result.values[4] = components.x
  result.values[5] = components.y
  result.values[0] *= components.scaleX
  result.values[1] *= components.scaleX
  result.values[2] *= components.scaleY
  result.values[3] *= components.scaleY
  if components.skew != 0:
    result.values[2] = result.values[0] * components.skew + result.values[2]
    result.values[3] = result.values[1] * components.skew + result.values[3]

proc width*(bounds: AABB): float32 = bounds.maxX - bounds.minX
proc height*(bounds: AABB): float32 = bounds.maxY - bounds.minY
proc center*(bounds: AABB): Vec2D =
  vec2((bounds.minX + bounds.maxX) * 0.5,
    (bounds.minY + bounds.maxY) * 0.5)
proc isEmptyOrNan*(bounds: AABB): bool =
  not (bounds.width > 0 and bounds.height > 0)
proc contains*(bounds: AABB; point: Vec2D): bool =
  point.x >= bounds.minX and point.x <= bounds.maxX and
    point.y >= bounds.minY and point.y <= bounds.maxY
proc offset*(bounds: AABB; x, y: float32): AABB =
  aabb(bounds.minX + x, bounds.minY + y, bounds.maxX + x, bounds.maxY + y)
proc join*(a, b: AABB): AABB =
  aabb(min(a.minX, b.minX), min(a.minY, b.minY),
    max(a.maxX, b.maxX), max(a.maxY, b.maxY))
proc intersection*(a, b: AABB): AABB =
  aabb(max(a.minX, b.minX), max(a.minY, b.minY),
    min(a.maxX, b.maxX), min(a.maxY, b.maxY))

proc mapBounds*(matrix: Mat2D; bounds: AABB): AABB =
  let corners = [
    matrix * vec2(bounds.minX, bounds.minY),
    matrix * vec2(bounds.maxX, bounds.minY),
    matrix * vec2(bounds.maxX, bounds.maxY),
    matrix * vec2(bounds.minX, bounds.maxY)]
  result = aabb(corners[0].x, corners[0].y, corners[0].x, corners[0].y)
  for index in 1 .. corners.high:
    result.minX = min(result.minX, corners[index].x)
    result.minY = min(result.minY, corners[index].y)
    result.maxX = max(result.maxX, corners[index].x)
    result.maxY = max(result.maxY, corners[index].y)

proc containFit*(content, destination: AABB): Mat2D =
  ## Centered contain fit. Returns identity for invalid source/destination.
  if content.isEmptyOrNan or destination.isEmptyOrNan: return IdentityMat2D
  let scale = min(destination.width / content.width,
    destination.height / content.height)
  let fittedWidth = content.width * scale
  let fittedHeight = content.height * scale
  let tx = destination.minX + (destination.width - fittedWidth) * 0.5 -
    content.minX * scale
  let ty = destination.minY + (destination.height - fittedHeight) * 0.5 -
    content.minY * scale
  mat2D(scale, 0, 0, scale, tx, ty)
