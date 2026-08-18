# 03 — Consumer-facing contract

The exact API shape and names belong to Spliney. The separate demo needs the
following documented interactions and invariants.

## Construction and discovery

The consumer must be able to:

1. Supply `.riv` bytes and any required rendering context to Spliney in a
   documented order.
2. Receive either a usable imported file or a structured failure.
3. Obtain the declared default artboard and its stable bounds.
4. Enumerate linear animations by stable file order with names and authored
   timing metadata.
5. Create independent mutable artboard/playback state for a selected animation.

The contract must state which objects own decoded image and graphics resources
and how long imported bytes or file definitions must remain alive.

## Frame operation

For a valid scene, the consumer needs a single canonical operation per frame
that accepts elapsed seconds and produces fully applied, dependency-settled
state ready to draw. It will be called exactly once with a finite positive
delta no greater than 0.1 seconds.

Drawing must accept caller-controlled destination/alignment and screen-space
placement without the consumer reaching into Spliney's internal object graph.

## Animation selection

When X selects another animation, the demo needs to replace mutable
artboard/playback state atomically:

- keep the imported file and reusable decoded image resources alive;
- create clean mutable state for the new animation;
- apply its authored start pose before the next timed advance;
- commit the new selection only after construction succeeds;
- leave the old selection usable if replacement construction fails;
- avoid re-reading the file or decoding all images again.

The demo will cycle indices modulo three in the order reported by Spliney.

## Errors and diagnostics

The consumer must be able to distinguish failures at these boundaries:

- asset/file read supplied by the consumer;
- Rive import or version compatibility;
- default artboard selection;
- playable-scene construction;
- embedded image decode;
- renderer or graphics-resource initialization;
- draw/capture.

Diagnostics should include relevant Spliney context and the consumer-supplied
asset path or label, but never raw binary contents.

## Reproducible package information

Spliney readiness documentation must identify the exact tested revision and
all information a sibling source-path consumer needs to reproduce the build:

- public imports and supported entry points;
- required Nim version and memory-management mode;
- exact registry/native dependencies and compatible versions;
- compile-time definitions and native link requirements, if any;
- graphics-context initialization order;
- resource destruction order;
- the canonical headless and macOS verification commands.

The demo must not depend on an undeclared package that happens to exist in one
developer's global Nimble cache.
