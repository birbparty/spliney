# Package

version       = "0.1.0"
author        = "Matt Spurlin"
description   = "A from-scratch Rive animation runtime in Nim (renderer-agnostic core + pluggable 2D backends)"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 2.0.0"
# Core stays dependency-light. Math libs (vmath/bumpy) are added by the math bead
# once confirmed portable to 3DS/Vita and compatible with the core-purity allowlist.

# Run the test suite. `nimble test` -> `make test` -> ralph's VERIFY step all route here.
task test, "Run the spliney test suite":
  # A dependency-free core compile cannot accidentally resolve Naylib/Raylib.
  exec "nim check --hints:off --mm:orc --noNimblePath tests/contracts/public_consumer.nim"
  exec "nim c -r --hints:off --mm:orc --outdir:build tests/generated/test_wire_registry.nim"
  exec "nim c -r --hints:off --mm:orc --outdir:build tests/io/test_loader.nim"
  exec "nim c -r --hints:off --mm:orc --outdir:build tests/math/test_geometry.nim"
  exec "nim c -r --hints:off --mm:orc --outdir:build tests/animation/test_easing.nim"
  exec "nim c -r --hints:off --mm:orc --outdir:build tests/core/transform/test_node.nim"
  exec "nim c -r --hints:off --mm:orc --outdir:build tests/scene/test_dependency.nim"
  # --outdir:build keeps compiled test binaries out of the source tree (build/ is gitignored).
  exec "nim c -r --hints:off --mm:orc --outdir:build tests/test_smoke.nim"
