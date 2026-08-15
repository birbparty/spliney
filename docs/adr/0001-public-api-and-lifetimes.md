# ADR 0001: public API, errors, and lifetimes

Status: accepted

Date: 2026-08-15

## Context

The goblin consumer needs one immutable imported definition, prepared image and
backend resources shared across animation selections, and independent mutable
playable scenes. Nim ORC collects ordinary ref objects, but native and GPU
resources still require deterministic release before a Raylib context closes.
The core must also remain importable without graphics dependencies.

## Decision

The public facade is exported by `import spliney` and defined in
`spliney/contracts`. It uses three opaque reference handles with distinct
lifetimes:

- `ImportedRiveFile` owns resolved immutable definitions and copies every
  compressed embedded payload needed after a successful import. It never
  borrows the caller byte buffer.
- `PreparedResources` owns decoded CPU images and backend resources for one
  imported file and one backend context. It is shared by scenes and is not
  recreated during animation selection.
- `PlayableScene` owns independent mutable component values, animation cursor,
  dependency dirt, solver scratch, and deformed vertices. It retains the
  immutable definition/resources it needs but never another scene.

The stable operations are:

- `importRive` and `loadRiveFile`;
- `defaultArtboard` with animations in stable file order;
- `prepareResources` after graphics-context creation;
- `newScene`, `initialSettle`, `advanceAndApply`, and transactional
  `replaceAnimation`;
- backend-neutral `draw` with a destination rectangle and post-fit
  screen-space translation; and
- overloaded, idempotent `close` for scenes, resources, and files.

`advanceAndApply` accepts only finite positive deltas at most 0.1 seconds. The
explicit `initialSettle` operation owns zero-time initialization. Scene
replacement constructs, applies the authored start pose, and settles a new
scene before swapping it into the caller variable. On any failure the old scene
must remain structurally and visually in lockstep with an untouched control.

Failures are returned as `SplineyResult[T]` or `SplineyStatus`. `SplineyError`
has a closed `ErrorCategory`, stable `ErrorStage`, sanitized message, and typed
context fields for labels, offsets, object/property keys, assets, and
animations. Raw bytes are never included. Programmer misuse is represented by
the lifecycle category in checked/test builds; expected input, construction,
backend, and capture failures are values rather than exception text.

Core imports never import Naylib, Raylib, Pixie, boxy, or platform graphics
headers. `ResourceFactory` and `RenderSink` are renderer-neutral public base
types; their concrete command/resource methods are finalized by the two
remaining Gate 0 backend decisions without changing the facade above.

ADR 0003 finalizes the image-resource side of that seam: the opt-in Raylib
adapter decodes retained compressed PNG bytes headlessly, normalizes owned CPU
images to straight RGBA8 top-to-bottom rows, validates dimensions, and uploads
separate textures only after a context exists. `PreparedResources` owns both
CPU images and textures and maps corrupt payloads to `assetDecode/imageDecode`.
No decoder type or Naylib import enters the facade or core module graph.

Shutdown order is mandatory:

1. stop drawing and close every `PlayableScene`;
2. close `PreparedResources` while the backend context is valid;
3. close `ImportedRiveFile`; and
4. close the Raylib window/context.

Every aggregate owner tracks successful acquisition stages. Rollback and
repeated `close` release each native resource at most once. Finalizers are only
a safety net and may not be the normal graphics cleanup path.

The compile-only fixture at `tests/contracts/public_consumer.nim` locks these
symbols through the public package barrel. Import, default-artboard discovery,
linear-animation scene construction, initial settle, bounded advance,
transactional replacement, and their lifecycle checks are implemented by the
Gate 2 exact-asset slice. Resource preparation and drawing retain structured
pending errors until their later gates, without changing the accepted contract.

## Rationale

Separating definitions, prepared resources, and mutable scenes makes resource
reuse and scene independence directly testable. Copying successful import data
removes an otherwise invisible caller-lifetime hazard. Returned typed errors
are stable across compiler/runtime message changes. Explicit close preserves
ORC convenience for ordinary object graphs without delegating context-bound
GPU destruction to nondeterministic collection.

## Alternatives considered

- Borrow caller bytes: rejected because successful playback must survive the
  caller releasing its read buffer.
- Mutate imported artboards directly: rejected because two scenes and failed
  transactional replacement must be independent.
- Decode/upload during every selection: rejected because resources are stable
  file/backend state and counters must remain unchanged during replacement.
- Rely only on ORC finalization: rejected because textures cannot outlive their
  context and partial construction needs deterministic rollback.
- Raise exception text as the API: rejected because consumers need closed,
  testable error categories and stages.
- Import the Raylib adapter from the package barrel: rejected because the core
  purity contract and headless ORC build are mandatory.

## Consequences

The runtime must track outstanding scene/resource ownership and validate the
shutdown sequence in lifecycle tests. Backend adapters remain opt-in modules.
The facade can add convenience overloads later, but the accepted operations,
positive-delta semantics, transactional guarantee, and close order may not be
silently weakened.
