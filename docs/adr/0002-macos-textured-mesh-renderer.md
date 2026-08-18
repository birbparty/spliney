# ADR 0002: macOS textured-mesh renderer

Status: accepted

Date: 2026-08-15

## Context

The pinned goblin asset reaches three deformed image meshes in every measured
state. Gate 0 therefore had to select exactly one macOS production route before
the importer and renderer were coupled: direct Naylib/Raylib textured
triangles, or a CPU textured-triangle rasterizer uploaded as a frame texture.
The decision must cover texture coordinates, color channels, alpha, opacity,
readback orientation, deterministic capture, and resource cleanup on the exact
asset rather than a synthetic triangle alone.

## Decision

Use direct `rlgl` triangle-list submission for the macOS adapter. WP3.4, the CPU
raster-to-texture fallback, is inactive and must not be implemented unless this
ADR is superseded with new failing evidence.

The non-shipping official-runtime probe exports, under the ignored private
evidence directory, all 13 original embedded PNG payloads and an isolated
CoreGraphics rendering of the first `Timeline 1` image-mesh command at zero
seconds. The Raylib spike renders that exact 40-vertex, 111-index mesh and a
known 2-by-2 RGBA fixture into a 960-by-540 render texture, reads it back, and
closes without user input.

The adapter conventions proven by the spike are:

- decoded image bytes are straight-alpha, top-row-first RGBA8;
- Rive UV `(0, 0)` samples the decoded top-left texel, so uploaded textures and
  UVs are not flipped;
- the affine array is `[xx, yx, xy, yy, tx, ty]`, applied as
  `(xx*x + xy*y + tx, yx*x + yy*y + ty)` before submission;
- sampler key 0 maps to Raylib bilinear filtering and clamp wrapping;
- indexed commands are expanded in index order into `RL_TRIANGLES`;
- vertex color alpha carries draw opacity while RGB remains white;
- source-over uses straight-alpha RGB factors `SrcAlpha` and
  `OneMinusSrcAlpha`, but alpha factors `One` and `OneMinusSrcAlpha`, with
  `FuncAdd` for both. Raylib's stock `Alpha` mode is insufficient because it
  applies `SrcAlpha` to the source alpha channel too;
- back-face culling stays disabled until the rlgl batch is flushed, because
  rlgl records vertices but applies raster state at flush time;
- render-texture readback is vertically inverted and receives exactly one
  `imageFlipVertical` before pixel comparison/export; and
- textures and render targets are destroyed before `closeWindow`; modified
  blend and culling state is restored before returning to the caller.

The fixed acceptance thresholds are:

- every known-pixel RGBA channel differs by at most 2;
- both representative foreground masks contain at least 9,000 pixels;
- representative foreground intersection-over-union is at least 0.95;
- mean absolute RGB error over the foreground union is at most 8.0; and
- at most 1,000 foreground-union pixels have any RGB channel error above 32.

The two byte-identical runs on the decision host produced 10,062 Raylib and
10,134 reference foreground pixels, 0.9823321555 IoU, 4.2948566942 mean
absolute RGB error, and 175 pixels over 32. The isolated CoreGraphics reference
SHA-256 is
`587e665e43eb69c6278275b51028cefe6763f3029171b0196b1ffaf4b524ed80`;
the Raylib capture SHA-256 is
`6631e04ffecdfc270dd97828ac04a0f62ebfb4b954a438f826da2a22677a6a2f`.
The remaining high maximum edge error is bounded to the 175-pixel count and is
consistent with CoreGraphics edge antialiasing versus rlgl triangle coverage;
it does not require a threshold exception.

The selected toolchain is macOS 26.5.2 arm64, Nim 2.2.10 with ORC, Apple clang
17.0.0, Naylib 26.08.0 at package revision
`19dd4e7e34c705c677e89b3a6516846c9f2e0125`, its Raylib binding constant
5.5.0, and its bundled Raylib source reporting 5.6-dev. The official-runtime
reference remains pinned to
`372b8092e940f32cf84499ae23a4899ec66a9ab1`. No private Raylib patch is used.

Repeat the passing experiment with explicit private evidence:

```bash
tools/run_raylib_render_spike.sh \
  --oracle build/private-evidence/goblin-oracle/first/oracle.json \
  --reference-dir build/private-evidence/goblin-oracle/first/reference \
  --output-dir build/private-evidence/raylib-render-spike
```

The wrapper compiles with `--mm:orc -d:useNaylib`, wakes a sleeping local
display with `caffeinate -u`, runs twice, and byte-compares both metrics JSON and
PNG capture. A valid macOS graphics context remains a production requirement.

## Discarded alternative

The CPU raster-to-texture route would duplicate bilinear sampling, clamping,
triangle coverage, blending, and upload ownership in Spliney. Direct rlgl meets
the predeclared known-pixel and exact-asset thresholds repeatably without a
private patch, so that extra renderer has no compensating benefit and would
create two production paths to maintain.

## Consequences

Gate 3 implements only direct textured triangles in the opt-in Raylib adapter.
The renderer-independent core continues to emit image/mesh commands and does
not import Naylib. The adapter must preserve the exact state, alpha, UV, flush,
readback, and teardown conventions above in its integration tests.
