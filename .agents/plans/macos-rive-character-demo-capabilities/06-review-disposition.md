# Review disposition

This file records review feedback applied to the plan. It is not live task
status; implementation work is tracked in Beads.

## Independent review pass — 2026-08-15

Two read-only reviewers independently checked the initial six-file draft: one
focused on architecture/contracts and one on delivery/evidence/task-graph
correctness.

### Accepted and applied

1. **Fix the dependency-arrow contradiction.** The architecture diagram now
   defines arrow meaning and shows both the facade and Raylib adapter importing
   inward; the core never imports the adapter.
2. **Give the visible `SolidColor`/`Fill` an owner and gate.** WP3.2 now owns
   exact visible command emission, and recording/headless exit evidence must
   assert the required solid fill rather than relying on final pixel tolerance.
3. **Decide PNG decoding explicitly.** New WP0.4 selects/pins the decoder,
   module boundary, headless/context behavior, alpha/pixel format, ownership,
   error mapping, and all-13-image proof.
4. **Strengthen the rendering-path decision and complete the fallback.** WP0.3
   now uses known pixels plus a representative actual-asset mesh snapshot with
   recorded decision thresholds. Conditional WP3.4 fully plans the CPU
   textured-triangle rasterizer when that path wins.
5. **Separate default-artboard failures from internal reference failures.** The
   error contract now requires distinct stable stages/categories.
6. **Cover all three animations with semantic oracles.** Gate 0 records, and
   Gate 2 checks, representative official bone/vertex states for every linear
   animation. The existing 0/2-second pixel oracle remains focused on
   `Timeline 1` as requested.
7. **Validate reference inputs before pixel comparison.** The pixel gate now
   requires the two supplied reference PNGs to match the authoritative hashes,
   dimensions, order, color mode, and alpha mode before calculating metrics.
8. **Make reset correctness observable.** After every repeated replacement,
   the selected start-state structural snapshot and recording draw hash must
   equal a separately constructed fresh scene, while shared resource identities
   stay stable.
9. **Name the exact Beads edges that leak unrelated scope.** The reconciliation
   plan now specifies splits around `spliney-65h`, `spliney-cxm`,
   `spliney-etw`, `spliney-kr1`, and the CPU raster kernel, and explicitly
   excludes the broad Phase 2/3/5 milestones from asset readiness.
10. **Treat Beads/remote sync as a gate.** The plan now requires resolution of
    the observed Dolt branch/no-common-ancestor errors, proof of pull/push, and
    Git/Dolt remote verification at handoff. The planning session completed
    that repair; implementation begins by verifying it remains green.

### Declined

None. All concerns identified a real ambiguity or false-positive path and were
incorporated without expanding the consumer scope.

## Adversarial review pass

One read-only reviewer then tried to make the revised plan fail or declare a
false success.

### Accepted and applied

1. **Remove the self-referential handoff revision.** Gates now test an immutable
   clean source commit; a report-only child commit carries evidence, stores the
   tested parent SHA, and is identified externally after its own SHA exists.
2. **Break the Gate 2/Gate 3 resource cycle.** Gate 2 shares immutable file data
   and embedded-asset handles only. Decode/upload identities and draw hashes are
   introduced and asserted in Gate 3.
3. **Render-validate all three animations.** Gate 0 now creates pinned official
   frame pairs for `Timeline 2` and `Timeline 3`; Gate 4 compares all three
   public-path animations, while preserving the authoritative request policy
   for `Timeline 1`.
4. **Replace weak “representative” solver samples.** The oracle now covers all
   bones, constraint outputs, reachable animated properties, all 107 deformed
   vertices, every skin/tendon/constraint/mesh, and complete visible draw-list
   state at fixed pre-implementation tolerances.
5. **Prevent same-bug reset comparisons.** Tests poison prior mutable state and
   compare every replacement start to independent official full-state/draw-list
   expectations, not only another Spliney scene.
6. **Prove resources are reused, not merely relabeled.** File-read, PNG-decode,
   GPU-upload, and acquisition counters must remain unchanged around every
   successful and failed animation swap.
7. **Make movement whole-scene and pixel-observable.** A padded capture compares
   every projected vertex and the entire foreground mask shifted exactly 100
   pixels, including vacated/background areas.
8. **Close the ROI loophole.** The plan defines `[210, 750) x [0, 540)` exactly
   and rejects non-background output outside it before applying inside-ROI
   metrics.
9. **Quantify lifecycle stress.** The plan fixes selection/frame/failure counts,
   baseline resource deltas, `leaks --atExit --` evidence, harness timeout, and
   post-window process-exit deadline.
10. **Test failed replacement continuation.** At every clone/start/settle
    failure, the old scene must continue structurally and visually in lockstep
    with an untouched pre-failure control.
11. **Pin all evidence producers.** The readiness record includes the sibling
    demo SHA plus every probe/oracle source and manifest hash needed to
    regenerate ignored private evidence.
12. **Run a truly external consumer.** Clean-checkout verification copies the
    minimal consumer into a package outside the Spliney checkout, connects it
    only through the documented sibling source-path mechanism, and exercises
    the real Naylib lifecycle through public imports.

### Declined

None. Each concern exposed a concrete false-positive or circular-gate risk and
was applied without adding unrelated Rive features.
