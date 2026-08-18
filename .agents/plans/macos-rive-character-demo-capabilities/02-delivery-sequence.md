# Delivery sequence

Each gate ends in executable evidence. Do not begin a later gate merely because
the source for an earlier one exists; its exit evidence must pass. Work packages
within the same gate may proceed in parallel only after their shared contracts
are settled.

## Gate 0 — Rebaseline and retire uncertainty

Goal: make the implementation path unambiguous before broad code generation or
public API work.

### WP0.1 — Pin inputs and produce a complete type audit

- Verify the private asset hash and official runtime revision.
- Extend or add a non-shipping probe that lists every serialized type key,
  property key, parent/reference relationship, animation keyframe/interpolator
  type, image dimension, mesh/index count, and the relevant constraint fields.
- Record all four bone/root-bone world matrices, both IK outputs, the transform
  constraint output, all reachable animated property values, and the full 107
  deformed mesh vertices at the start and at least one non-trivial time for each
  linear animation. Include 0 and 2 seconds for `Timeline 1`.
- At those states, record the official visible draw list: stable drawable/image
  identity and order, fill parameters, world/presentation transforms, opacity,
  blend/sampler state, UVs, indices, and final deformed positions.
- Before runtime implementation, map every skin, tendon, constraint, mesh, and
  animated property to at least one oracle field/state. Fix comparison
  tolerances at no more than `1e-4` artboard units absolute or `1e-5` relative
  unless an ADR backed by repeatability measurements justifies a narrower
  type-specific exception.
- Produce official 960 by 540 reference frame pairs for `Timeline 2` and
  `Timeline 3` at their chosen non-trivial times, using the same background,
  alignment, alpha mode, and probe reproducibility rules as `Timeline 1`.
- Store only redistributable manifests/hashes; keep asset bytes and derived
  images out of Git until rights are known.

Exit evidence: two probe runs are byte-identical, the asset SHA matches, every
reachable solver/render branch maps to a fixed oracle field and frame pair, all
oracle/reference files have recorded hashes and tolerances, and there are no
unexplained serialized types reachable from the visible/update graph.

### WP0.2 — Write the public API/lifetime ADR

- Define import, default-artboard discovery, animation enumeration, scene
  construction, initial settle, per-frame advance, draw placement, transactional
  selection, structured errors, and explicit disposal as semantic contracts.
- Include a compiling pseudo-consumer showing window/context initialization and
  destruction order. Exact symbol names are decided here.
- Decide whether the imported file owns a byte copy and how prepared image/GPU
  resources relate to it.

Exit evidence: ADR accepted, a compile-only consumer fixture locks the proposed
API shape, and ownership is unambiguous for success and partial failure.

### WP0.3 — Select one macOS drawing path

- Build a Naylib experiment that first uploads a known 2-by-2 RGBA texture,
  then submits a representative multi-triangle mesh/image snapshot exported by
  the non-shipping exact-asset probe. Composite source-over onto the declared
  background, capture pixels, and close automatically.
- Verify texture origin, UV convention, channel order, premultiplication,
  opacity, readback orientation, and cleanup under the exact toolchain.
- Define decision thresholds for both known-pixel accuracy and the
  representative asset snapshot. Choose direct textured triangles only if the
  experiment meets them repeatably. Otherwise select CPU raster-to-texture and
  activate WP3.4.

Exit evidence: an ADR names one production path, records the discarded path and
reason, pins dependencies/flags, states whether WP3.4 is active, and includes a
repeatable passing command and capture metrics.

### WP0.4 — Select and pin the PNG preparation path

- Compare the smallest viable decoder choices for 13 embedded PNGs, including
  whether Raylib's image decoder can run without a graphics context and without
  leaking adapter imports into the core.
- Decide the dependency/version, module boundary, decode-time pixel format,
  row orientation, alpha convention, error mapping, and CPU-image ownership.
- Prove headless decode and post-window GPU upload are either separate supported
  stages or document why the chosen production Factory requires a context.
- Decode every exact embedded payload through a non-shipping test harness and
  record dimensions/hashes without committing private derived pixels.

Exit evidence: the API/lifetime ADR pins one decoder path and all dependencies,
the core-purity test remains satisfiable, and all 13 payloads decode with
stable metadata while corrupt-PNG failures map to the asset-decode stage.

Gate 0 is serial at the decision points: WP0.1 informs the API/model floor;
WP0.2, WP0.3, and WP0.4 may then finish in parallel and must be reconciled into
one API/lifetime/dependency contract before Gate 1.

## Gate 1 — Safe import and immutable file definition

Goal: turn exact bytes into a resolved, inspectable definition without graphics
or animation mutation.

### WP1.1 — Deterministic generated wire metadata

- Pin the official defs source and implement a generator for type keys,
  property keys, defaults, inheritance, and backing types.
- Generate the complete major-version registry; hand-written runtime types plug
  into it without editing generated files.
- Add a regeneration-diff test and collision/duplicate-key validation.

### WP1.2 — Bounds-checked binary importer

- Implement primitive reads, header/ToC parsing, object/property stream,
  unknown-property skip, typed failures with offsets, and allocation limits.
- Add truncation, overflow, impossible-length, bad-reference, and unsupported
  major tests before using the private fixture.

### WP1.3 — Object resolution and definition inventory

- Implement import-stack/reference resolution and stable file ordering.
- Materialize artboard, animation metadata, embedded image metadata/bytes, and
  all concrete model types from the Gate 0 audit.
- Add reachable-output support classification. Unknown or unimplemented
  output-affecting records are fatal; named inert records are retained in the
  import report.

Exit evidence: the exact file imports headlessly with no output-affecting
warnings and reports the declared artboard, animations, embedded assets,
meshes, bones/skins/weights, and constraints. Malformed/unsupported fixtures
return their exact error category without crashes or raw-byte diagnostics.

WP1.1 precedes WP1.2 and the generated base of WP1.3; resolution/model bodies
may be split by non-overlapping directories after the registry is stable.

## Gate 2 — Independent playback and dependency evaluation

Goal: produce correct, mutable, draw-ready geometry without a GPU.

### WP2.1 — Mutable artboard and scene construction

- Clone instance state from immutable definitions while sharing only immutable
  file data and stable embedded-asset handles. Gate 2 does not require decoded
  CPU/GPU resources, which are introduced in Gate 3.
- Expose default-artboard bounds and animations in source order.
- Construct every animation on clean state and settle its authored start pose.
- Prove two simultaneous instances do not affect one another.

### WP2.2 — Linear animation timing and property application

- Implement the keyed object/property/frame types actually found by WP0.1.
- Ground and test interpolation, authored speed/direction, loop mode, duration,
  fps, start/work area, wrap behavior, and large-but-valid host delta handling.
- At Gate 2, make transactional selection reuse the imported file and stable
  embedded-asset handles while replacing only mutable scene state. Gate 3 adds
  the equivalent assertion for prepared CPU/GPU resources.

### WP2.3 — Dependency graph, bones, skins, and constraints

- Build deterministic dependency order with cycle detection and dirt
  propagation.
- Implement transform composition, bones/root bones, tendons, weights, skins,
  IK constraints, and transform constraint behavior needed by the asset.
- Update deformed mesh vertices only after all dependencies settle.
- Cross-check the complete Gate 0 numeric/draw-list oracles at every fixed state
  for all three animations before pixel work.

Exit evidence: fixed-step headless sequences for all three animations are
deterministic, change over time, match their official intermediate values,
remain independent across concurrent scenes, and survive repeated
transactional selection. Before each replacement, poison every addressable
animated property and solver scratch field on the old scene. The replacement's
full structural start snapshot must match the independently recorded official
start-state oracle for that animation, not merely another Spliney scene. On
every injected clone/start/settle failure, advance the old scene alongside an
untouched control and require identical structural continuation.

WP2.1 and the dependency skeleton may progress together after Gate 1. WP2.2
and individual solver components may then progress in parallel, but WP2.3's
numeric gate integrates them before Gate 3.

## Gate 3 — Embedded images and renderable textured meshes

Goal: turn settled scene state into backend-neutral commands backed by valid
image resources.

### WP3.1 — Embedded PNG preparation

- Implement the Factory/decode seam selected by the ADR.
- Decode all 13 in-band PNG payloads, validate dimensions, retain ownership,
  and share resources across scenes.
- Add deterministic failure injection for each decode/acquire stage and verify
  rollback.
- Count file reads, PNG decodes, GPU uploads, and resource acquisitions. Capture
  the baseline after preparation and require every counter to remain unchanged
  across successful and failed animation swaps.

### WP3.2 — Exact visible draw-command emission

- Define/implement the solid-color fill command proven visible by WP0.1 plus
  image and indexed-mesh commands with positions, UVs, `uint16` indices,
  sampler behavior, opacity, blend mode, and current transform.
- Own the minimum fill/path geometry needed by this asset here or in an explicit
  prerequisite bead; assert its presence and parameters in the recording
  backend so a missing fill cannot hide inside final pixel tolerances.
- Preserve stable drawable order and avoid per-frame recreation of immutable
  buffers/resources.
- Add a recording backend that hashes commands and validates indices, finite
  coordinates, resource handles, and transform-stack balance.

### WP3.3 — Alignment and movement

- Implement contain-fit and alignment in the backend-neutral layer.
- Compose screen-space translation after fitting.
- Add numeric tests proving a 100-pixel translation remains 100 pixels for
  differently sized source/destination rectangles.

### WP3.4 — Conditional CPU textured-triangle rasterizer

This package is required only when WP0.3 selects CPU raster-to-texture.

- Rasterize already-resolved solid and textured triangles into the declared
  RGBA/premultiplication format; do not couple this kernel to general path or
  stroke tessellation.
- Implement the selected sampler, source-over blending, opacity, bounds/clipping,
  texture orientation, and deterministic conversion to a Raylib-uploadable
  image.
- Test single/overlapping triangles, shared edges, degenerate/out-of-bounds
  geometry, UV corners, alpha ramps, and the representative actual-asset mesh
  snapshot against known pixels.
- Upload one composed frame texture without reallocating immutable asset data
  per animation selection.

Exit evidence: the CPU branch's known-pixel and representative-snapshot tests
meet the WP0.3 thresholds and its output texture has a documented owner and
upload/disposal lifecycle.

Gate 3 exit evidence: the exact asset emits a non-empty, deterministic draw
stream at 0 and 2 seconds containing the required solid fill and three textured
meshes; all 13 resources remain valid across repeated animation swaps; command
hashes and geometry change where expected; every fresh/replaced scene's start
draw-command content matches the official draw-list oracle and replacement
hashes match separately fresh Spliney scenes; read/decode/upload/
acquire counters remain at the preparation baseline; and resource/transform
stacks return to baseline after every draw/failure. After each injected
replacement failure, the old scene's next draw hash must match its untouched
control. If active, WP3.4 also passes.

WP3.1, WP3.2, and WP3.3 can run in parallel once their Gate 0/ADR interfaces
are frozen. WP3.4 can run alongside them when activated; all selected packages
then integrate at the exit gate.

## Gate 4 — Actual macOS Naylib/Raylib path

Goal: render and capture the exact asset using the same public seam the external
demo will consume.

### WP4.1 — Adapter and lifecycle

- Implement only the drawing path chosen in WP0.3.
- Create GPU/native resources after `initWindow`; destroy them before
  `closeWindow`.
- Map texture/mesh commands, transforms, opacity, source-over blending, and
  premultiplied/straight-alpha conversions explicitly.
- Keep adapter imports out of the core barrel unless the consumer opts in.

### WP4.2 — Finite-frame capture harness

- Use the public facade to import, select `Timeline 1`, settle at 0, render, then
  advance in finite positive steps no greater than 0.1 until exactly 2 seconds
  and render again.
- Use 960 by 540, the declared background, centered contain-fit, and the actual
  Raylib capture/readback path. Exit automatically on every success/failure.
- Emit PNG hashes and all comparison metrics in a machine-readable result.
- Repeat the same public-path capture for `Timeline 2` and `Timeline 3` at their
  Gate 0 timestamps and compare them to their pinned official frame pairs. Use
  the same strict channel-error thresholds; their own reference foreground/
  changed-pixel counts define the relative-area/change expectations.
- Capture translated and untranslated frames on a canvas with at least 100
  pixels of horizontal safety margin. Verify every final projected vertex has
  delta `(100, 0)`, the full foreground mask is an exact 100-pixel shift, and
  vacated/outside pixels remain background.

Exit evidence: two repeat runs are stable on the pinned host/toolchain, all
three animations pass their official frame-pair comparisons, `Timeline 1`
satisfies every authoritative threshold in the request, and the process closes
without a crash or lingering process. The padded translation capture proves
whole-scene 100-pixel placement.

## Gate 5 — Hardening and consumer handoff

Goal: make the passing vertical slice reproducible and safe to consume from a
sibling project.

### WP5.1 — Failure and lifecycle matrix

- Exercise bad file bytes/version, missing artboard, unsupported reachable
  type, every image decode/upload stage, scene construction, renderer init,
  draw/capture, repeated replacement, and cleanup after partial construction.
- Run address/leak tooling available on macOS plus internal acquire/release
  counters. Require idempotent explicit disposal and no use after context close.
- Fix the stress profile at 300 complete modulo-three selection cycles (900
  replacements), 10,000 bounded headless advances, 600 rendered frames, and 50
  repetitions of every injected acquisition/construction failure. After warmup,
  all Spliney-owned live-object/byte/texture/buffer counters must return exactly
  to baseline after each batch and show no upward trend.
- Run the finite lifecycle harness under macOS `leaks --atExit --` (or a named,
  pre-approved equivalent if unavailable), retain its report, require zero
  definitely-lost allocations attributable to Spliney, enforce a 120-second
  test timeout, and require the process to exit within five seconds after
  window close.

### WP5.2 — Package and documentation contract

- Pin Nim/Nimble, Naylib/Raylib, registry/native dependencies, compile defines,
  link flags, and memory manager.
- Document public imports/symbols, error handling, asset labels, initialization,
  selection, per-frame operation, drawing, shutdown, and private-fixture setup.
- Provide canonical core-only, headless-private, macOS capture, and comparison
  commands. No command may depend on an undeclared global Nimble cache package.

### WP5.3 — Clean-checkout reproduction

- Reproduce from a separate clean checkout and clean dependency cache with the
  private asset/reference paths supplied explicitly.
- Record exact revisions, dependency graph, commands, output, capture hashes,
  metrics, skips, and environment details in a readiness artifact.
- Copy the committed minimal-consumer fixture into a temporary directory
  outside the Spliney checkout, initialize it as its own Nimble package, point
  it at Spliney solely through the documented sibling source-path mechanism,
  and build/run its actual Naylib window, import, selection, advance, draw, and
  shutdown flow. No Spliney test-only modules or implicit repository-relative
  paths are allowed.
- Hand the exact tested Spliney revision and public contract back to the demo
  repository so its failed consumer manifest can be replaced.

Exit evidence: the complete verification matrix passes, all public docs match
the independently located consumer package, the clean-checkout record is
complete, and the demo team can consume Spliney without local knowledge or
internal imports.

## Implementation stop conditions

Stop the current gate and resolve a decision when:

- the private asset or official pin differs;
- the complete type audit finds a new output-affecting feature outside the
  request inventory;
- direct Raylib rendering cannot meet the color/alpha/pixel contract;
- the public ownership model permits a texture to outlive its context or scene
  state to outlive definitions;
- an error path cannot roll back deterministically; or
- meeting a threshold appears to require weakening it rather than fixing the
  implementation.

Record the resolution in an ADR and update this plan/Beads dependencies before
continuing.
