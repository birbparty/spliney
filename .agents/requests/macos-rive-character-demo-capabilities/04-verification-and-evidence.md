# 04 — Verification and readiness evidence

Readiness requires evidence at the same scope as the requested behavior. API
presence, successful imports, draw-call counts, or issue closure alone are not
sufficient.

## Exact input

All asset-specific checks must use bytes with SHA-256
`7a2f1d58da22e12932e73e76366b48651e66d9980153ece5433188c8fd08bc35`.
If those bytes change, the official inventory and references must be regenerated
before comparing Spliney output.

The asset can remain outside Spliney's tracked tree if licensing is uncertain.
Tests may accept an explicit local path and fail or skip with a clear reason
when the private fixture is unavailable, but a passing readiness claim must
include a recorded run with the exact asset.

## Headless evidence

A headless test should demonstrate, at minimum, that Spliney can:

- import the file without output-affecting unsupported-object warnings;
- report one default artboard, three linear animations, thirteen image assets,
  three image meshes, two IK constraints, and one transform constraint;
- create each animation scene on clean mutable artboard state;
- advance a deterministic fixed-step sequence;
- produce non-empty drawing or structural output that changes over time;
- repeatedly replace playback across every animation without stale handles or
  stale animated properties;
- clean up after every construction stage and failure stage exercised by the
  public contract.

Structural evidence complements but does not replace pixel evidence.

## macOS rendering evidence

Using Spliney's actual consumer-facing Naylib/Raylib path, a finite-frame test
must capture the same scene at 0 and 2 seconds and exit automatically. It must
fail on import, decode, renderer initialization, drawing, capture, or cleanup
errors.

For each 960 × 540 capture on the declared background:

- at least 256 pixels and at least 0.5% of the reference ROI must differ from
  the background;
- foreground area must remain within 75%–125% of the official reference;
- the actual 0-second and 2-second frames must differ by at least 32 pixels and
  at least 50% of the official changed-pixel count;
- within the official ROI, mean absolute RGBA channel error must be at most 2;
- no more than 1% of compared pixels may have any channel delta greater than
  16.

The authoritative official frame hashes, dimensions, ROI, timestamps, alpha
mode, and regeneration command are in the demo's committed asset manifest.
Generated images can remain untracked while rights are unresolved.

If repeatable backend antialiasing makes the final two pixel thresholds
inappropriate, any exception must be explicit and reviewable: identify the
approver, date, both frame hashes, observed metrics, and concrete reason. The
non-empty foreground and changed-frame gates still apply.

## Consumer-reproduction evidence

Before handoff, another clean checkout should be able to reproduce Spliney's
headless and macOS tests from documented commands and pinned dependencies. The
record should include:

- Nim and Nimble versions;
- Spliney revision;
- external package revisions;
- compile definitions and native link configuration;
- resolved dependency graph;
- test and capture command output;
- reference/capture hashes and comparison metrics.
