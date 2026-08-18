# macOS goblin consumer contract

This contract covers the exact Rive 7.3 goblin vertical slice. The asset label
is caller-supplied and sanitized errors report it as `g0bl1ntest.riv`; the
private bytes are never redistributed by Spliney.

## Build inputs

- Nim 2.2.10, Nimble 0.22.2, C backend, `--mm:orc`;
- Spliney through an explicit sibling `--path:/absolute/path/spliney/src`;
- Naylib 26.08.0 revision
  `19dd4e7e34c705c677e89b3a6516846c9f2e0125`, aggregate SHA-256
  `a705b3fc7987785b6609780a0237e92f380705a357faee8a30af8b26275dc1ae`;
- `-d:useNaylib` and `--path:/absolute/path/naylib`; and
- Naylib’s bundled Raylib 5.6-dev native sources and default macOS
  OpenGL/Cocoa frameworks. No patched or forked Raylib is used.

The package-level `spliney` import remains graphics-free. A macOS consumer
imports only these public modules:

```nim
import raylib
import spliney
import spliney/backends/raylib/renderer
```

## Lifecycle

1. Call `loadRiveFile(path, "g0bl1ntest.riv")` and inspect `isOk` before using
   the returned `ImportedRiveFile`.
2. Read `defaultArtboard()` for stable animation metadata.
3. Call Raylib `initWindow` before `prepareResources(newRaylibFactory())`.
4. Create a scene with `newScene(0, animationIndex)`, then call
   `initialSettle()` once.
5. Per frame, call `advanceAndApply(dt)` with finite `0 < dt <= 0.1`, reset the
   `RaylibRenderer`, enter the Raylib render target/window drawing scope, and
   call `draw(resources, renderer, destination, optionalScreenTranslation)`.
6. Use `replaceAnimation(index)` for atomic linear-animation selection. A
   failed replacement leaves the old scene usable.
7. Close scenes, render targets, and `PreparedResources` before
   `closeWindow()`. Close the `ImportedRiveFile` last. Explicit close is
   idempotent at every Spliney layer.

Every fallible Spliney operation returns `SplineyResult[T]` or `SplineyStatus`.
On failure, inspect `category`, `stage`, `message`, and sanitized `context`;
never read `.value` from a failed result. Render backend failures propagate
through `draw` as `render/drawSubmission` errors.

The independently compiled package at
`tests/consumer/goblin_demo/` is the executable reference. It uses no internal
or test-only imports and exercises real window creation, all three animation
selections, bounded advances, public drawing, and shutdown.

## Supported exact slice

The tested asset includes one 500-by-500 artboard, three linear animations, 13
embedded PNGs, a visible solid fill, three textured meshes, bones/skins, two IK
constraints, and one transform constraint. State machines remain imported
metadata only. Nested artboards, clipping, text, audio, scripting, general path
tessellation, console rendering, and Boxy are outside this milestone.

Use the four canonical commands in [tools/README.md](../tools/README.md) for
core, private headless, macOS capture, and clean-checkout readiness. Those
commands require every private path explicitly and fail on a missing fixture,
pin mismatch, skipped readiness test, or undeclared cached dependency.
