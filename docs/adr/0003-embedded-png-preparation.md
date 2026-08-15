# ADR 0003: embedded PNG preparation

Status: accepted

Date: 2026-08-15

## Context

The pinned goblin file contains 13 in-band PNG payloads. Spliney's core must
remain usable without graphics dependencies, while the macOS adapter needs one
bounded decoder, stable pixels, explicit ownership, and a separate GPU upload
stage. Gate 0 compared using Raylib's existing image decoder with adding a
second PNG package to the dependency graph.

## Decision

Use Naylib's `loadImageFromMemory(".png", payload)`, backed by Raylib's bundled
stb_image implementation, in the opt-in `spliney/adapters/raylib_images` module.
Do not add Pixie, lodepng, a second stb_image binding, or an application-owned
decoder. The version pin is Naylib 26.08.0, package revision
`19dd4e7e34c705c677e89b3a6516846c9f2e0125`; the binding constant is Raylib
5.5.0 and the bundled source reports 5.6-dev.

The boundary is split into two stages:

1. The adapter borrows each immutable compressed payload only for the decode
   call. Decode needs no window or graphics context. The returned Raylib
   `Image` owns its allocation and is immediately normalized with
   `imageFormat(..., UncompressedR8g8b8a8)`.
2. After a valid Raylib context exists, the adapter creates one `Texture2D`
   from each retained CPU image. `PreparedResources` owns both sets and releases
   textures, then images, before the window closes.

Decoded pixels are straight-alpha RGBA8 in top-to-bottom row order. There is no
decode-time or upload-time row flip. ADR 0002's known-pixel test proves the
top-row/UV mapping, and its exact-asset comparison proves the convention against
the official CoreGraphics output. Render-texture readback has its own single
vertical flip and does not change this resource contract.

The adapter validates decoded width and height against immutable asset metadata
and associates resources by stable embedded-asset identity, not filename. A
decode failure returns `ErrorCategory.assetDecode` at `ErrorStage.imageDecode`
with the asset id and the sanitized message `embedded PNG decode failed`; native
exception text and payload bytes do not cross the adapter seam. Allocation,
normalization, validation, or upload failure releases every resource acquired
so far exactly once. Animation selection never decodes or uploads again.

The private Gate 0 probe decoded all 13 exact payloads twice before creating a
window and byte-compared their normalized buffers and reports. It then retained
the pre-context CPU images, created a context, uploaded all 13, destroyed every
texture before `closeWindow`, and finally released the CPU images. The two
headless reports have SHA-256
`4a9590943d3d57c3e9859f4e0b1e5cdeda0ffc87b8b072d3c4d693ab24ae6e7a`;
the normalized-hash list has SHA-256
`67a02359ed8b0a125099f4857dd99ecb551cb3bb6ad732b799c130966d8961f2`.
A payload with its eight-byte PNG signature overwritten produced the required
structured error.

Repeat the experiment with explicit private evidence:

```bash
tools/run_raylib_png_decode_probe.sh \
  --oracle build/private-evidence/goblin-oracle/first/oracle.json \
  --reference-dir build/private-evidence/goblin-oracle/first/reference \
  --output-dir build/private-evidence/raylib-png-decode
```

The core-purity gate compiles the public consumer with `--noNimblePath`; the
Raylib adapter and this probe are compiled separately with `-d:useNaylib`.

## Alternatives considered

- A separate stb_image binding exposes the same implementation while adding a
  second wrapper, allocator boundary, and version pin. It provides no useful
  capability after Raylib proved headless decoding.
- Pixie adds broader image and drawing features that this fixed PNG-only asset
  slice does not need and would risk leaking renderer concerns into the core.
- lodepng is smaller in scope but still duplicates a decoder already shipped
  by the selected backend and creates another pixel/error/ownership contract.
- Decoding only after window creation is workable but needlessly couples CPU
  validation to the graphics lifecycle and makes headless verification weaker.

## Consequences

Gate 3 implements the selected adapter seam without changing the public facade.
The renderer-neutral importer retains compressed bytes and metadata; it never
imports Raylib. The macOS adapter is responsible for decode normalization,
dimension validation, GPU acquisition, error mapping, counters, rollback, and
ordered close. Four exact payloads decode initially as gray+alpha and are
therefore deliberately expanded to RGBA8 alongside the other nine.
