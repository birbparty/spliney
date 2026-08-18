# Risks and decision gates

## Decisions that must be made early

| Decision | Default direction | Decide by | Evidence required |
|---|---|---|---|
| Public API and error shape | semantic facade over definitions/resources/scenes; closed error categories | Gate 0 | compiling external-consumer fixture and failure examples |
| Ownership under ORC | explicit idempotent disposal for GPU/native resources; immutable shared definitions/assets; independent scenes | Gate 0 | lifecycle ADR and partial-failure model |
| Imported byte lifetime | imported file owns what it needs after construction | Gate 0 | test that releases caller buffer before playback |
| Wire registry breadth | generate complete pinned major-version metadata; hand-implement asset-relevant runtime behavior | Gate 1 | deterministic generator and complete byte-stream audit |
| Layout style handling | implement relevant properties or prove inert for exact asset | Gate 1 | official bounds/placement comparison |
| macOS render route | direct Naylib/Raylib textured triangles first | Gate 0 | known-pixel plus representative exact-asset mesh capture covering alpha/UV/orientation/readback; otherwise activate WP3.4 CPU fallback |
| Embedded PNG decoder | one pinned, headless-capable preparation path behind the render-resource seam | Gate 0 | all 13 payloads decode, corrupt input fails structurally, core purity and ownership remain explicit |
| Alpha convention | match declared premultiplied reference at comparison boundary | Gate 0/4 | known-pixel compositing test and captured metadata |
| Private fixtures | explicit local paths; never auto-discover; absence fails readiness only | Gate 0 | fixture policy and SHA checks |

## Main risks and mitigations

### The committed asset inventory is not a full parser manifest

Risk: selected feature counters omit animation/interpolator/support objects, so
implementers discover required types late.

Mitigation: WP0.1 enumerates the complete object/property stream and reachability
before defining the model floor. Unknown visible/update records stop the gate.

### The existing Beads phases impose unrelated prerequisites

Risk: state machines, clipping, nested artboards, or broad vector rendering delay
the exact consumer even though its visible graph is image-mesh based.

Mitigation: create an asset-specific milestone with artifact dependencies and
split reusable slices from broad beads. Preserve future work without putting it
on this critical path.

### Parser success hides semantic corruption

Risk: the file imports and emits draw calls while skipped layout, constraint, or
mesh fields produce the wrong character.

Mitigation: classify reachable support, assert exact inventory, compare
intermediate bone/vertex state, then enforce final pixel thresholds. Import-only
and draw-count-only tests cannot close a gate.

### Official and consumer stepping differ

Risk: the official reference was selected by seeking/advancing to a timestamp,
while the consumer contract advances once per frame with deltas no greater than
0.1.

Mitigation: record the Spliney step sequence and require its final state to
match official numeric/pixel oracles. If official constraint results depend on
step subdivision, regenerate an additional official stepped oracle without
overwriting the authoritative manifest, document the distinction, and resolve
the runtime semantics before Gate 4.

### A Spliney-vs-Spliney reset comparison hides shared defects

Risk: a replacement and a fresh scene can share the same wrong default pose or
omitted property, while stable wrapper ids can hide rereads/redecodes.

Mitigation: poison prior mutable state, compare every replacement start against
the independent official full-state oracle for that animation, continue the old
scene against an untouched control after injected failure, and assert file-read,
decode, upload, and acquisition counters do not change during selection.

### GPU alpha, texture origin, or readback differences swamp correct geometry

Risk: straight/premultiplied conversion, vertical flips, sRGB handling, sampler
state, or blend mode causes large pixel errors.

Mitigation: the Gate 0 capture tests each variable with known pixels and a
representative exact-asset mesh/image snapshot. Record conventions at every
boundary and choose one render route before asset integration; if CPU rendering
wins, activate the explicit WP3.4 raster-kernel branch.

### Constraint defects are hard to localize from final images

Risk: transform order, IK iteration, weights, or solve ordering yields plausible
but wrong pixels.

Mitigation: pin complete bone/constraint/property/vertex and draw-list oracles
at the fixed states for all animations, map every solver/render branch to an
oracle field, and add focused synthetic unit fixtures before golden rendering.

### Native resources outlive the Raylib context

Risk: ORC timing or failed construction destroys textures after `closeWindow`,
or repeated selection double-frees/shared-frees them.

Mitigation: explicit aggregate owner, idempotent disposal, strict documented
shutdown order, failure injection at each acquisition, resource counters, and
tests that make context teardown observable.

### Private licensing blocks automated CI

Risk: the exact asset/reference PNGs cannot be committed, so ordinary CI passes
without exercising readiness.

Mitigation: keep a public synthetic suite and a separately named required
private readiness command. The readiness record must show a recorded exact-SHA
run; a skip never counts as green. Seek redistribution permission separately,
without blocking local verification.

### Dependency drift breaks a sibling consumer

Risk: a developer's Nimble cache or system Raylib supplies undeclared packages,
headers, or link flags.

Mitigation: pin every dependency, test in a clean cache/checkout, capture the
resolved graph and commands, and build/run a real Nimble consumer package in a
separate temporary directory using only the documented sibling source-path
dependency and public imports.

### Evidence commits become self-referential

Risk: a committed report cannot truthfully contain the SHA of the commit that
contains itself, so “exact handoff revision” can name untested or impossible
state.

Mitigation: test an immutable clean source commit, create a report-only child
commit, store the tested source SHA inside the report, and identify the child
evidence-carrier SHA externally in the handoff/tag after it exists.

### Scope expands toward full Rive parity

Risk: generated complete metadata is mistaken for a requirement to implement
state machines, nested artboards, text, or other absent features.

Mitigation: separate wire-level recognition from runtime support. Implement
only reachable behavior needed for the exact asset plus reusable prerequisites;
return structured unsupported-output errors elsewhere.

## Escalation rules

Escalate for an explicit product/engineering decision when:

- the asset audit contradicts the request inventory;
- a required feature would add a new native dependency or change the core
  purity contract;
- the selected adapter would require patching/forking Naylib or Raylib;
- correct output requires changing public frame semantics;
- deterministic cleanup cannot be expressed safely with the chosen ownership
  model;
- the exact comparison thresholds cannot pass on the pinned environment; or
- redistribution of any private/derived file is proposed.

Record the decision in an ADR with options, evidence, choice, consequences, and
the Beads/plan changes it causes.

## What not to optimize yet

Do not put console support, boxy integration, general vector tessellation,
state-machine playback, hot-path allocation budgets, installers, or universal
Rive compatibility on the demo-readiness critical path. Preserve the seams they
need, but optimize performance only after correctness, ownership, and exact
asset evidence pass. Add a bounded performance smoke check to catch pathological
behavior; do not let premature benchmarks replace the visual contract.
