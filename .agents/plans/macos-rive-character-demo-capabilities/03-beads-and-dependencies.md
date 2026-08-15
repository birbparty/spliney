# Beads and dependency reconciliation

## Why the current graph needs a focused rebaseline

The existing Beads graph describes a broad multi-platform Rive runtime. It is
useful source material, but its milestone chain places raster meshes after
state machines and constraints after nested-artboard work. This exact consumer
needs raster meshes and constraints but does not need state-machine playback or
nested artboards. Following the existing phase milestones literally would add
unrelated work to the critical path.

Before implementation, create an asset-specific epic/milestone and update the
graph so this plan is represented in Beads. Do not use this Markdown plan as
live status tracking after that conversion.

Beads synchronization was repaired during this planning session: the stale
one-issue remote lineage was reconciled to the current full graph, `main` now
tracks `origin`, and normal `bd dolt pull`/`bd dolt push` both pass. Re-run both
commands before creating the implementation graph and stop if either regresses.
A local-only task graph is not a valid starting state.

## Reuse existing beads where their acceptance matches

Retain and, where necessary, strengthen these existing work items:

| Capability | Existing beads | Required adjustment |
|---|---|---|
| Grounded wire metadata/import | `spliney-04t`, `f45`, `hoz`, `a5z` | Add deterministic generation pin, complete stream audit, structured error categories, and exact-asset import acceptance |
| Memory/render seam | `spliney-cpb`, `dyg`, `k37` | Make deterministic explicit graphics cleanup and transactional scene ownership part of acceptance |
| Math/scene/animation | `spliney-61d`, `999`, `o1b`, `65h`, `oin`, `ke4`, `u15` | Add independent instances, zero-time settle, canonical positive-delta frame API, exact timing metadata, and numeric oracle checks |
| Draw commands | `spliney-cxm`, `fvx` | Add indexed image-mesh command validation and transform-stack/resource invariants |
| Assets/meshes | `spliney-atk`, `7c2`, `etw`, `ef4` | Promote exact embedded PNG decode and mesh output to this consumer's critical path; avoid treating decode as optional here |
| Constraints | `spliney-jpn` | Split or narrow acceptance to IK + transform constraints plus bones/skins/tendons/weights needed by the exact asset |
| Raylib | `spliney-myc`, `dgf`, `kr1`, `1n0` | Time-box the macOS path decision and keep only the selected production route; add exact asset/capture policy |
| Documentation/package | `spliney-1dz`, `t10`, `x1i`, `125` | Add sibling source-path reproduction, pins, public lifecycle/errors, and clean-cache proof |

Vector-only shape/tessellation beads remain dependencies only if the complete
type audit or selected Raylib path proves they affect this asset's visible
output. Do not inherit them merely from the broader Phase 1 milestone.

## Exact scope-leaking edges to replace for the asset slice

Do not mutate broad reusable beads until their future intent is understood.
Prefer splitting out narrow asset-slice beads, then give the broad bead a
dependency on the completed slice where that preserves work. Encode these
specific changes:

- Split the exact-asset artboard/instance/draw-order slice from `spliney-65h` so
  it depends on the dependency solver and audited asset model, not automatically
  on `spliney-2kw`/`spliney-eyy` general paths/primitives. Add only the focused
  solid-fill prerequisite proven by WP0.1.
- Split exact visible emission from `spliney-cxm`. The slice depends on the
  renderer seam, asset artboard slice, focused solid fill, and image-mesh
  protocol; it must not inherit `spliney-052` clipping. Keep the original broad
  path/paint/clip bead and its clipping dependency for future vector scope.
- Split the asset image-mesh implementation from `spliney-etw`. Its input is
  already indexed/deformed triangles, so replace the inherited
  `spliney-2kw -> spliney-cxm` path chain with audited mesh model, skin/constraint
  solve, renderer protocol, and exact visible emission dependencies.
- If direct desktop submission wins, split a macOS image-mesh adapter from
  `spliney-kr1`; depend on WP0.3, the renderer protocol, and asset draw commands,
  not `spliney-32y` fill triangulation or `spliney-al2` stroke expansion.
- If CPU raster wins, split the triangle raster kernel from `spliney-k3g`; the
  kernel consumes triangles and depends on math/render protocol, not the
  general path/stroke tessellators. Point the asset Raylib adapter at that
  kernel rather than inheriting the console-focused breadth of `spliney-dgf`.
- Make the new readiness milestone depend directly on the resulting slices.
  Do not depend on `spliney-6qr`, `spliney-40g`, or `spliney-jy8`, whose current
  chains include state machines and nested-artboard work.

## Add asset-specific beads

Create separately claimable work for gaps that are not represented today:

1. Complete pinned asset type/property and numeric solver oracle probe.
2. Public consumer API, error taxonomy, and ownership/lifecycle ADR plus
   compile-only external-consumer fixture.
3. Exact-asset headless inventory/playback/reselection integration test.
4. Exact-asset failure-injection and deterministic cleanup matrix.
5. Exact-asset macOS finite-frame capture/comparator, including 100-pixel
   placement proof.
6. Clean-checkout/private-fixture reproduction record and demo handoff.
7. Asset-specific readiness milestone depending on the exact required reusable
   beads and the six items above.

Descriptions should embed the corresponding plan section and measurable exit
evidence. Use narrow directory ownership to allow safe parallel work.

## Dependency shape to encode

```text
asset audit -----> generated registry -----> importer/resolution
      |                                      |
      |                                      v
      +-----> API/lifetime ADR -----> instance/playback
      |               |                      |
      |               |                      v
      |               +-----------> dependency/constraint solve
      |                                      |
render spike -> render protocol <---- mesh command emission
      |               ^                      ^
      |               |                      |
      +-----> raylib adapter <----- PNG/resource preparation
                              \       /
                               capture
                                  |
           headless + lifecycle + pixel + clean checkout
                                  |
                    asset-specific readiness milestone
```

State-machine playback, clipping, nested artboards, text, console backends,
boxy, and general state-machine milestones must not block the asset-specific
readiness milestone.

## Suggested Beads conversion order

1. Reconfirm normal Dolt pull/push before task-graph edits; the ancestry/tracking
   repair completed during planning must remain green.
2. Create the asset-specific epic/milestone and the new decision/probe beads.
3. Add the new acceptance language to reusable existing beads without erasing
   broader valid scope.
4. Split existing beads when the exact-asset slice can be independently tested
   and completed; make the broader bead depend on the slice if appropriate.
5. Add dependencies from actual artifact flow, not historical phase numbers.
6. Run `bd lint`, `bd orphans`, `bd blocked`, and `bd ready`; inspect that at
   least Gate 0 work is ready and unrelated scope is not on the critical path.
7. Record the plan directory in the epic design field and stop updating status
   in Markdown.
8. At each implementation session handoff, follow repository protocol: reconcile
   upstream Git and Dolt changes, run `bd dolt push`, push Git, and verify both
   task data and the source branch are present/up to date on their intended
   remotes. Treat any no-common-ancestor error as unresolved, not a warning to
   ignore.

## Parallel ownership rules

- Generated registry files have one owner. Runtime class implementations plug
  into generated interfaces rather than editing generated output by hand.
- Public facade and lifetime/error types have one owner until the Gate 0 ADR is
  accepted.
- Core, decoder, Raylib adapter, test harness, and documentation directories
  can have separate owners after their interface contracts are frozen.
- Exact-asset tests may be developed alongside implementation but cannot be
  weakened to match incomplete output.
- A reviewer who changes pixel thresholds or approves an exception may not be
  the sole implementer of the rendering change under review.

## Milestone closure rule

Close the asset-specific readiness milestone only when the verification record
links to passing source/tests/captures and a clean tested revision. Closing
individual implementation beads, compiling APIs, or producing non-empty draw
commands is not readiness evidence.
