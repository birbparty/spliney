import std/[math, unittest]

import spliney/math/geometry

proc close(a, b: float32; tolerance = 0.00001'f32): bool = abs(a - b) <= tolerance
proc close(a, b: Vec2D): bool = close(a.x, b.x) and close(a.y, b.y)
proc close(a, b: AABB): bool =
  close(a.minX, b.minX) and close(a.minY, b.minY) and
    close(a.maxX, b.maxX) and close(a.maxY, b.maxY)

suite "Rive-compatible core geometry":
  test "vector operations are allocation-free value math":
    let a = vec2(3, 4)
    check a.length == 5
    check a.normalized.close(vec2(0.6, 0.8))
    check a.dot(vec2(2, -1)) == 2
    check a.cross(vec2(2, -1)) == -11
    check lerp(vec2(0, 10), vec2(10, 0), 0.25).close(vec2(2.5, 7.5))

  test "matrix storage multiplication and mapping match Rive":
    let parent = translationMat2D(10, 20) * rotationMat2D(PI.float32 / 2)
    let local = scaleMat2D(2, 3) * translationMat2D(4, 5)
    let composed = parent * local
    let point = composed * vec2(1, 2)
    check point.close(parent * (local * vec2(1, 2)))
    check translationMat2D(10, 20).transformDirection(vec2(2, 3)) == vec2(2, 3)

  test "inverse is transactional for singular matrices":
    let matrix = translationMat2D(12, -7) * rotationMat2D(0.7) * scaleMat2D(2, 3)
    var inverse = IdentityMat2D
    require matrix.inverse(inverse)
    let identity = matrix * inverse
    for index, expected in IdentityMat2D.values:
      check close(identity.values[index], expected)
    let previous = inverse
    check not scaleMat2D(0, 1).inverse(inverse)
    check inverse == previous
    check scaleMat2D(0, 1).inverseOrIdentity == IdentityMat2D

  test "transform decomposition and composition match Rive":
    let components = TransformComponents(
      x: 12, y: -3, scaleX: 2, scaleY: -0.75,
      rotation: 0.42, skew: 0.18)
    let roundTrip = components.compose.decompose
    check close(roundTrip.x, components.x)
    check close(roundTrip.y, components.y)
    check close(roundTrip.scaleX, components.scaleX)
    check close(roundTrip.scaleY, components.scaleY)
    check close(roundTrip.rotation, components.rotation)
    check close(roundTrip.skew, arctan(components.skew))

  test "bounds and contain fit cover translated aspect ratios":
    let bounds = aabb(-10, -20, 30, 20)
    check bounds.width == 40
    check bounds.height == 40
    check bounds.center == vec2(10, 0)
    check bounds.contains(vec2(-10, 20))
    check bounds.join(aabb(20, -30, 40, 10)) == aabb(-10, -30, 40, 20)
    check bounds.intersection(aabb(20, -30, 40, 10)) == aabb(20, -20, 30, 10)
    check rotationMat2D(PI.float32 / 2).mapBounds(
      aabb(0, 0, 10, 20)).close(aabb(-20, 0, 0, 10))

    let wide = containFit(aabb(10, 20, 110, 70), aabb(0, 0, 200, 200))
    check (wide * vec2(10, 20)).close(vec2(0, 50))
    check (wide * vec2(110, 70)).close(vec2(200, 150))
    let translated = translationMat2D(100, 0) * wide
    check (translated * vec2(10, 20)).close(vec2(100, 50))
