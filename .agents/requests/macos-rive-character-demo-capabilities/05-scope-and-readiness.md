# 05 — Scope and readiness handoff

## Required scope

This request is limited to the behavior needed for the exact supplied asset and
the standalone macOS consumer:

- Rive 7.3 import sufficient for the asset's object graph;
- default artboard and linear-animation discovery;
- correct linear animation playback and clean selection reset;
- the asset's skeletal deformation, image meshes, IK constraints, and
  transform constraint;
- embedded PNG decoding;
- faithful macOS Naylib/Raylib presentation;
- diagnostics, ownership, cleanup, documentation, and verification.

Supporting an object only in name is not sufficient when it materially affects
the official reference output.

## Not requested for this consumer

The asset inventory does not make these capabilities prerequisites for the
demo:

- state-machine-driven playback or state-machine inputs;
- clipping shapes or nested artboards;
- text or fonts;
- audio;
- scripting;
- data binding;
- app bundles, signing, notarization, or installers;
- non-macOS rendering targets;
- changes to Inputty or the demo's keyboard behavior;
- a general-purpose implementation of every Rive feature.

The file contains one state machine and one layout style object. They must not
prevent safe import or corrupt linear playback, but this request does not ask
the demo to drive state-machine behavior.

## Consumer constraints

The standalone demo must exercise Spliney as an external sibling dependency.
It will not vendor Spliney, copy its internal types, parse `.riv` records
itself, extract embedded PNGs, implement local skinning/constraints, or link the
official C++ runtime as a fallback.

The asset and official runtime are behavioral oracles, not shipped demo
dependencies.

## Readiness handoff

The request is satisfied when Spliney can provide a clean revision plus the
evidence in `04-verification-and-evidence.md`, and its public documentation
fully answers the consumer-contract questions in `03-consumer-contract.md`.

At handoff, the demo team should be able to replace its current failed
`docs/spliney-consumer-manifest.md` with exact tested imports, symbols,
dependency pins, initialization and cleanup order, and passing commands from
that Spliney revision. Only then will the demo proceed to application
scaffolding and integration.

The readiness decision is based on source, tests, captures, and reproducible
commands—not on implementation intent, planned issues, or partial feature
milestones.
