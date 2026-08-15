# 00 — Context and desired outcome

## Consumer goal

The requesting consumer is a standalone Nim application for macOS. It needs to
load one user-supplied Rive file through Spliney, render and advance its default
character animation, move the whole rendered artboard in screen space, and
select the next linear animation without reloading the file.

The application uses Inputty for keyboard input and Naylib/Raylib for its
window and drawing edge. This request concerns only the Spliney capabilities
needed at that integration boundary.

## Desired outcome

Spliney is ready for the consumer when a clean, documented revision can:

1. Import the exact asset without corruption or output-affecting warnings.
2. Expose its default artboard and three linear animations in file order.
3. Create independent mutable playback state and advance each animation with
   correct timing and dependency updates.
4. Decode and retain the asset's embedded PNG images.
5. Render its textured, skinned image meshes with the required constraints so
   the result matches the official-runtime references.
6. Present that output through a macOS-compatible Naylib/Raylib integration.
7. Report actionable errors and release all runtime and graphics resources
   safely.
8. Document enough of the tested public contract for a separate Nim project to
   consume Spliney without relying on unrecorded local setup.

## Why this request exists

The demo plan intentionally stops before application scaffolding when Spliney
cannot satisfy the supplied asset. Building the app against placeholder APIs,
reimplementing Rive behavior in the demo, or falling back to the official C++
runtime would conceal the actual dependency gap rather than demonstrate
Spliney consumption.

## Solution-neutral boundary

This request does not select:

- internal modules or directory layout;
- object representation or memory-management implementation;
- parsing, animation, constraint, skinning, tessellation, or rasterization
  algorithms;
- CPU versus GPU rendering internals;
- task order or assignment;
- names or signatures for public symbols.

Those decisions remain with Spliney. The consumer only needs the behavior and
evidence described in this request.
