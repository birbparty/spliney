# 02 — Required capabilities

This document states required observable behavior. It intentionally does not
specify how Spliney should implement that behavior.

## Import and file model

Spliney needs to accept the exact `g0bl1ntest.riv` bytes and distinguish at
least successful import from malformed data, unsupported format/version,
unsupported output-affecting content, and asset decode failures. Errors must
carry enough context for a consumer to identify the failed layer without
printing raw asset bytes.

On successful import, the consumer needs to discover the declared default
artboard, its stable source bounds, and its playable scene inventory. Importing
the file must not silently discard or corrupt objects that materially affect
the reference output.

## Mutable artboard and playback state

The consumer needs independent mutable artboard state rather than mutation of
shared file definitions. It must be possible to create a fresh playable scene
for any of the three linear animations in stable file order.

Playback must honor the authored fps, duration, speed, direction, loop mode,
and start/work-area semantics. A newly selected animation must be able to begin
from its authored start pose on clean mutable state, without properties from
the previously selected animation remaining stale.

For each frame, the consumer needs one documented playback-level operation
that advances time, applies animation data, and leaves all dependencies settled
for drawing. The consumer should not need to know or reproduce different
internal update passes for different object types.

## Skeletal deformation and constraints

The animated character relies on bones, root bones, skins, tendons, weights,
IK constraints, and a transform constraint. Spliney needs to evaluate the
parts of that graph that affect the three image meshes, in the correct
dependency order, so mesh geometry and image placement match the official
runtime over time.

Support is successful only when it produces the correct visible result. Merely
accepting or skipping these object records is insufficient.

## Embedded images and textured meshes

All thirteen PNGs are embedded in the `.riv` file. Spliney needs to decode the
required images from in-band contents and make them available to drawing
without separately extracted files. The consumer needs clear failure reporting
if any required image cannot be decoded.

All three image meshes must draw with their animated vertex positions, texture
coordinates, indices, opacity, and blending sufficiently faithfully to satisfy
the comparison gate. Image and graphics resources must remain valid for the
lifetime of every scene that uses them.

## Drawing and presentation

The standalone app needs a documented macOS-compatible path from a Spliney
artboard to Naylib/Raylib presentation. It must render a non-empty frame from
this asset and preserve the expected color, alpha, blending, and transformed
mesh appearance.

The consumer needs to place the stable artboard bounds inside a supplied
destination rectangle using contain-fit alignment, then apply an additional
screen-space translation for player movement. A movement of 100 screen pixels
must move the final presentation by 100 screen pixels regardless of the
artboard's source dimensions.

## Resource ownership and cleanup

Spliney needs a documented ownership contract covering imported file data,
mutable artboard and scene state, decoded images, renderer state, and graphics
resources. Normal shutdown, failed partial construction, and repeated animation
selection must not leak, double-release, or use graphics resources after their
required context is gone.

Cleanup must be deterministic enough for the demo to close on Escape or native
window close without a crash or lingering process.
