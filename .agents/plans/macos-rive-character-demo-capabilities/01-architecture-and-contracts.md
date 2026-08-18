# Architecture and consumer contracts

## Architecture boundary

Use one-way import dependencies. In the diagram, `A -> B` means that A may
import/depend on B:

```text
public facade -> runtime core -> render protocol
raylib adapter -------------> runtime core
raylib adapter --------------------------> render protocol
```

The runtime core must build and run headlessly under ORC. Importing `spliney`
must not implicitly import Naylib, Raylib, Pixie, boxy, or platform graphics
headers. The adapter may depend on the core and render protocol; the reverse is
not allowed. Add a fail-closed import/purity test to preserve this boundary.

Suggested ownership directories are `src/spliney/io`, `generated`, `core`,
`animation`, `scene`, `render`, `decode`, and `backends/raylib`, matching the
existing Beads reservations where possible. Exact public symbols should be
settled by an ADR and a compile-tested consumer example before broad
implementation.

## Definitions, instances, and resources

Keep three lifetimes distinct:

| Lifetime | Contains | Mutability and sharing |
|---|---|---|
| Imported file | Parsed definitions, stable file order, compressed embedded bytes, source bounds, diagnostics | Immutable after successful resolution; shared by scenes |
| Prepared resources | Decoded image metadata/pixels and backend textures/buffers | Shared by scenes from one imported file/backend context; explicitly disposed before the graphics context |
| Playable scene | Artboard component values, dependency dirt, animation cursor/direction/loop state, deformed vertices | Mutable and independent per selection; cheap to replace |

The imported file must not borrow caller bytes unless the public documentation
explicitly requires them to outlive it. Prefer copying/owning the compressed
embedded payload during import so a caller can release its read buffer after a
successful construction.

Scene replacement is transactional:

1. Keep the current scene and shared file/resources alive.
2. Construct a new artboard instance for the selected animation.
3. Apply the authored start pose and run a zero-time dependency settle.
4. Commit the new scene only after all steps succeed.
5. Dispose the old scene after the swap; on failure, return a structured error
   and leave the old scene usable.

“Usable” is behavioral: after a failed replacement at any construction stage,
the old scene must advance and draw in lockstep with an untouched control scene
from the same pre-failure state. It must match the control's structural snapshot
and draw-command hash, not merely remain non-null.

No scene may retain a raw pointer into another scene, a temporary import
buffer, or a resource owned by the consumer rather than the imported/prepared
resource owner.

Instrument file reads, PNG decodes, GPU uploads, and resource acquisitions in
tests. A successful or failed animation replacement must not increment those
counters; stable-looking wrapper identities alone do not prove resource reuse.

## Import and compatibility policy

Generate wire metadata from the pinned official `dev/defs/*.json` rather than
hand-copying numeric type/property keys. Check in the generator, its pin, and
deterministic generated output. The generated layer should cover the complete
wire registry for the pinned major version; runtime behavior may remain limited
to the asset-relevant concrete types.

The importer must:

- validate `RIVE`, major compatibility, the ToC, lengths, indices, references,
  numeric ranges, and EOF without out-of-bounds reads;
- skip unknown properties using their declared backing types;
- deserialize the full flat stream before resolving parent/reference links;
- distinguish malformed input, unsupported major/version, unresolved
  reference, asset decode, and output-affecting unsupported content;
- retain a typed diagnostic for known benign records that are intentionally not
  executed; and
- reject any unimplemented record reachable from the selected artboard's
  update or draw graph when its visual impact cannot be proven absent.

The one state machine may be retained as discoverable metadata without a
playback implementation. It must not break linear-animation import. The layout
style object is not automatically benign: compare bounds and draw placement
with the official inventory, then either implement the properties that affect
this artboard or record evidence that the object is inert for this file.

## Asset-relevant runtime model

At minimum, the resolved model must implement the types and inherited
properties needed for:

- `Artboard`, `Node`, `SolidColor`, and `Fill`;
- four `Bone`, two `RootBone`, two `Skin`, six `Tendon`, and 81 `Weight`
  objects;
- two `IKConstraint` and one `TransformConstraint`;
- 13 `Image`, three `Mesh`, and 107 `ContourMeshVertex` objects;
- the linear-animation/keyed-property/keyframe/interpolator records actually
  present in all three animations; and
- `LayoutComponentStyle` only to the extent required by the bounds/inertness
  decision above.

The committed probe's feature counts are a floor, not a complete serialized
type manifest. Add an importer audit that reports every encountered type and
property so implementation coverage is based on the actual byte stream, not
only the probe's selected feature counters.

## Frame semantics

Expose one canonical scene-level operation with these semantics:

```text
advanceAndApply(dt):
  validate finite 0 < dt <= 0.1
  advance the selected linear-animation cursor using authored speed/direction
  honor fps, duration, loop, and enabled work-area boundaries
  evaluate and apply keyed properties to the mutable artboard instance
  propagate dirt and settle dependencies in topological order
  update bones, skins, constraints, transforms, and deformed mesh vertices
  return state ready for draw, or a structured runtime error
```

Provide a separate explicit initial-settle operation or documented zero-time
construction behavior; do not weaken the positive-delta frame contract merely
to initialize a scene. Animation time is continuous seconds; authored fps maps
frames to time and does not require quantizing host deltas unless the asset's
metadata says so.

Advancing one scene must not mutate file definitions, shared decoded images, or
another scene. Unit tests should run two instances of the same animation at
different times and compare both against a fresh baseline.

## Dependency solve contract

Build a deterministic dependency order after import/reference resolution and
rebuild it only when topology changes. Animation writes mark dirt; dependency
evaluation processes prerequisites before dependents and detects cycles with a
structured construction failure.

Ground transform composition, bone/root-bone world transforms, tendon/weight
normalization, skin deformation, IK solve order, constraint strength, and
transform-constraint spaces directly against the pinned official source.
Capture the complete Gate 0 numeric/draw-list oracle from the official runtime:
all bone/root matrices, constraint outputs, reachable animated properties, and
all deformed vertices at the fixed states for every animation. Use those
oracles and their predeclared tolerances to localize solver defects before
debugging final pixels.

## Render protocol and placement

The renderer-independent protocol needs state save/restore, concatenating
transforms, opacity, images, indexed textured meshes, and the solid-color fill
operation proven reachable by the asset audit. Implement path/fill geometry
only to the extent that visible `SolidColor`/`Fill` requires it, with a focused
recording-backend test and explicit owner in Gate 3; retain clean extension
points for the broader existing plan.

Define placement as two explicit matrices:

```text
presentation = screenTranslation * containFit(destination, artboardBounds)
finalVertex  = presentation * artboardWorld * deformedVertex
```

Document matrix convention and multiplication order. Test contain-fit for wide,
tall, equal-aspect, and translated destinations. The translation is expressed
in destination/screen pixels and is applied after fitting, so `(100, 0)` changes
every final projected drawable/mesh vertex by exactly `(100, 0)`. On a padded,
unclipped capture canvas, the entire foreground pixel mask must equal the
untranslated mask shifted 100 integer pixels, with the vacated area restored to
the declared background.

For the macOS adapter, start by evaluating Naylib/Raylib's low-level
textured-triangle submission on desktop. Submit indexed triangles with animated
positions, UVs, image sampling, draw order, opacity, and source-over blending.
A decision spike at Gate 0 must prove the required texture orientation and
premultiplied-alpha behavior with readback using both known pixels and a
representative actual-asset mesh snapshot. If it cannot meet the decision
criteria without a private Raylib patch, select the fully planned
CPU-raster-to-texture branch in Gate 3; do not carry two production paths after
the decision.

## PNG and graphics-resource contract

The prepared resource layer must decode all embedded PNGs from in-band bytes,
validate dimensions and decode failures, and associate images by stable asset
identity rather than filename alone. Decode/upload once per prepared file and
reuse across animation selections.

Graphics resource creation occurs only while a valid context exists. Cleanup
order is:

1. stop drawing and dispose playable scenes;
2. dispose backend mesh buffers/textures and decoded-image owners;
3. dispose the imported file/definitions; and
4. close the Raylib window/context.

Provide an explicit idempotent `close`/`dispose` contract for native/GPU
resources even under ORC. Finalizers may be a safety net but are not the normal
cleanup path. Partially initialized aggregate owners track which stages
succeeded so rollback releases each acquired resource exactly once.

## Error contract

Use a closed error category plus a stable stage discriminator and contextual
fields, not exception text as the only API. Required categories/stages are:

- consumer file read/label context;
- malformed Rive data;
- incompatible/unsupported format;
- output-affecting unsupported content;
- internal object/reference resolution;
- default-artboard discovery/selection;
- playable-scene construction or invalid frame delta;
- embedded image decode;
- backend/context/resource initialization;
- draw/capture; and
- cleanup/lifecycle violation detected in tests.

Diagnostics may contain the consumer-supplied path/label, object type/property
keys, asset name/id, animation name/index, and causal chain. They must never
dump raw asset bytes. Define which failures are returned values and which are
programmer-contract assertions before freezing the public API.
