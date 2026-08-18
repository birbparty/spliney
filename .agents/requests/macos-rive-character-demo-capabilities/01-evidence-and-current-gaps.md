# 01 — Evidence and current gaps

## Inspected revisions

The readiness inspection was performed on 2026-08-15 against:

- Spliney `e3e7e5a72fc8a128934fab9410bf2bd21e8fe63f`.
- Official Rive runtime `372b8092e940f32cf84499ae23a4899ec66a9ab1`.
- Nim `2.2.10` on arm64 macOS `26.5.2`.

At that Spliney revision, `src/spliney.nim` exports only the package version and
`splineyVersionString`. There are no runtime implementation modules beneath
`src/spliney/`. The only automated test imports the package and checks its
version string.

The current public surface therefore provides none of the consumer behavior in
this request. This is a snapshot of observed source and tests, not a judgment
about planned work or issue status.

## Authoritative asset inventory

The tracked probe imported and rendered the asset with the pinned official
runtime twice, producing byte-identical manifests and PNGs. It established:

- Rive format version `7.3`.
- One default artboard named `Artboard`, bounds `500 × 500`.
- Three linear animations in file order:
  - `Timeline 1`: 24 fps, 192 frames, 8 seconds, speed 2, looping.
  - `Timeline 2`: 60 fps, 32 frames, approximately 0.533333 seconds, looping.
  - `Timeline 3`: 60 fps, 32 frames, approximately 0.533333 seconds, looping.
- One state machine named `State Machine 1` with no inputs. Linear animation
  playback is sufficient for this consumer, but the file must still import
  safely with that machine present.
- Thirteen embedded PNG assets, all decoded successfully by the official
  runtime, and thirteen image drawables.
- Three textured image meshes with 107 contour mesh vertices.
- A skeletal deformation graph containing four bones, two root bones, two
  skins, six tendons, and 81 weights.
- Two IK constraints and one transform constraint.
- One solid color and one fill used by the visible graph.
- One layout component style object that must not cause import corruption or
  visibly incorrect bounds/presentation.
- No clipping shapes, nested artboards, text, fonts, audio, scripting, or data
  binding objects required by this asset.

The object counts above come from the official-runtime inventory and its
generated type definitions. They are important because a vector-only or
unskinned raster implementation cannot produce the expected character.

## Official visual evidence

The official CoreGraphics renderer produced 960 × 540 premultiplied RGBA
references on a `[245, 247, 250, 255]` background:

| Time | PNG SHA-256 | Foreground pixels |
|---|---|---:|
| 0 seconds | `ac3e882aee9eb8a9ec1f8786a6084160fe1002ee935a9289211130048d6d8cef` | 291,600 |
| 2 seconds | `f617ff1b0a89c16b09f3afb8c0e001d5158da7775b82c27d8faf66bc88e7f126` | 291,600 |

The frames differ at 22,558 pixels, demonstrating visible animation. Their
declared foreground ROI is `(210, 0)–(749, 539)`.

## Current capability gaps

At the inspected Spliney revision, there is no source or test evidence for:

- Rive byte import, version handling, or structured import errors;
- default artboard discovery or mutable instances;
- animation discovery, timing, application, looping, or reset behavior;
- dependency propagation for skeletal animation;
- bones, skins, tendons, weights, IK constraints, or transform constraints;
- embedded image asset decoding and lifetime management;
- textured image-mesh drawing;
- drawing command emission or a macOS Naylib/Raylib presentation path;
- contain-fit alignment into a caller-provided destination;
- deterministic runtime and graphics cleanup;
- asset-specific headless or pixel validation;
- a documented consumer dependency and initialization contract.

Passing the current version-string smoke test does not provide evidence for any
of those capabilities.
