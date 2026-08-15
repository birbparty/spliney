# macOS Rive character demo capabilities

Status: reviewed implementation plan

Project: `spliney`

Change type: `NEW_FEATURE`

Prepared: 2026-08-15

## The outcome in one sentence

Deliver a clean Spliney revision that can import the pinned `g0bl1ntest.riv`,
play any of its three linear animations on independent mutable state, evaluate
its bones/skins/constraints, decode its 13 embedded PNGs, render its three
textured meshes through Naylib/Raylib on macOS, and prove the result against
the official-runtime references.

## Read this first

The shortest useful path through this plan is:

1. Read this page for the map and scope.
2. Read [01-architecture-and-contracts.md](01-architecture-and-contracts.md)
   before changing public or ownership APIs.
3. Execute the gates in [02-delivery-sequence.md](02-delivery-sequence.md) in
   order; work within a gate may run in parallel where shown.
4. Reconcile the existing Beads graph using
   [03-beads-and-dependencies.md](03-beads-and-dependencies.md) before starting
   implementation.
5. Treat [04-verification-and-evidence.md](04-verification-and-evidence.md) as
   the definition of done, not as a final cleanup phase.
6. Resolve the decisions in [05-risks-and-decision-gates.md](05-risks-and-decision-gates.md)
   at the named gates rather than improvising mid-implementation.

Reviewer feedback and its disposition are recorded in
[06-review-disposition.md](06-review-disposition.md).

## Critical path

```text
pinned evidence + API/lifetime ADR
              |
generated wire metadata -> safe importer -> immutable file definition
              |                              |
              +------------------------------+
                             |
             mutable scene + linear animation apply
                             |
          dependency order + bones/skins/IK/transform
                             |
       embedded PNG decode + textured mesh command emission
                             |
               macOS Naylib/Raylib adapter
                             |
       exact-asset structural, lifecycle, and pixel gates
                             |
                clean-checkout consumer handoff
```

State-machine playback, nested artboards, clipping, text, audio, scripting,
data binding, installers, signing, and non-macOS rendering are not on this
critical path.

## Scope guardrails

- The exact asset SHA-256 is
  `7a2f1d58da22e12932e73e76366b48651e66d9980153ece5433188c8fd08bc35`.
- The behavior oracle is Rive runtime
  `372b8092e940f32cf84499ae23a4899ec66a9ab1`; it is test evidence, not a
  shipped dependency.
- The consumer must use public Spliney APIs. It may not parse Rive records,
  extract images, solve constraints, or link the official runtime.
- Core parsing, animation, and scene evaluation remain renderer-agnostic.
  Naylib/Raylib code stays in an adapter module.
- Unknown records are never silently accepted when they can affect the chosen
  artboard's visible output. Benign ignored records must be named and tested.
- Private asset/reference files may stay outside Git until redistribution
  rights are established. A skipped private-fixture gate is not a passing
  readiness result.
- The implementation may support more than this asset when that falls naturally
  out of a reusable design, but general Rive parity cannot block this handoff.

## Measurable finish line

The work is complete only when all of these are true:

- Import reports the default `Artboard` at 500 by 500 and the three declared
  animations in stable file order with exact timing metadata.
- Each animation can be selected on fresh mutable state without rereading the
  file or decoding all images again.
- One canonical frame operation with `0 < dt <= 0.1` advances animation,
  applies properties, and settles dependencies before drawing.
- All 13 embedded PNGs decode; all three animated image meshes render with the
  required skinning, IK, and transform constraint behavior.
- Every animation produces a Naylib/Raylib frame pair that matches its pinned
  official-runtime oracle; `Timeline 1` additionally passes the request's
  authoritative 0/2-second comparison policy.
- Contain-fit plus a 100-pixel screen translation moves the final presentation
  exactly 100 screen pixels, independent of source-artboard dimensions.
- Structured failures and deterministic, idempotent cleanup work for normal
  shutdown and every injected partial-construction failure.
- The 960 by 540 captures at 0 and 2 seconds pass every threshold from the
  request through the actual Naylib/Raylib path.
- A separate clean checkout can reproduce the build, headless run, macOS
  capture, comparison metrics, and dependency resolution from documented
  commands and pins.

## Source basis

This plan is grounded in:

- `.agents/requests/macos-rive-character-demo-capabilities/`;
- `docs/reference/rive-runtime-reference.md`;
- the existing Spliney Beads graph as inspected on 2026-08-15;
- `/Users/punk1290/git/spliney-goblin-demo/docs/asset-manifest.json` and its
  companion manifest/gap report;
- the local official runtime checkout at the pinned commit; and
- the private input at `/Users/punk1290/Downloads/g0bl1ntest.riv`.

The Spliney repository was still a version-only scaffold when this plan was
written, so file/module names below are intended ownership boundaries rather
than promises about exact public symbol spelling.
