# Verification and evidence plan

## Test pyramid

### Unit and generated-data tests

- Binary reader: valid encodings, malformed/truncated data, integer overflow,
  impossible lengths, ToC packing, unknown property skip, and byte offsets.
- Generator: pinned input revision, deterministic output, unique keys,
  inheritance/defaults/backing types, and regeneration diff.
- Math: matrix convention/composition, inverse/singular cases, bounds,
  contain-fit, and post-fit screen translation.
- Animation: property types/interpolation found by the asset audit, authored
  fps/duration/speed/direction/loop/work-area semantics, wrapping, and invalid
  deltas.
- Dependency solving: topological ordering, dirt propagation, cycle failure,
  bone/skin/weight/IK/transform-constraint fixtures, and deterministic vertices.
- Resources: decode failures, identity mapping, reference ownership,
  idempotent close, and partial-construction rollback.
- Render protocol: stack balance, concatenating transforms, draw order, UV/index
  validation, opacity/blend mode, and stable recording hashes.

### Public-contract tests

Compile and run only through exported modules. Cover:

- imported caller bytes may be released at the documented point;
- default artboard and animation enumeration in stable file order;
- two independent scenes from one file/resource owner;
- canonical finite positive `dt <= 0.1` advance and explicit initial settle;
- atomic failed/successful animation replacement;
- destination/alignment and pixel-space movement without internal graph access;
- every structured error category and sanitized diagnostic fields; and
- correct explicit shutdown order.

### Exact-asset headless gate

Require an explicit asset path and verify its SHA before reading expectations.
The test must assert:

- Rive 7.3 import with no output-affecting unsupported diagnostics;
- default `Artboard`, 500 by 500 bounds, and three animations in exact order;
- exact authored animation timing metadata from the manifest;
- 13 image assets, three meshes, two IK constraints, one transform constraint,
  and the complete importer type/property audit;
- successful decode/validation of all 13 embedded PNGs using the selected
  preparation path, without requiring separately extracted files;
- clean construction and deterministic fixed-step advance for every animation;
- non-empty structural/draw output that changes over time;
- the full Gate 0 oracle at every selected state: all bone/root-bone matrices,
  both IK outputs, transform-constraint output, reachable animated properties,
  and all 107 deformed vertices, within the pre-implementation fixed
  tolerances, with explicit coverage of every skin/tendon/constraint/mesh;
- official draw-list content at each state, including drawable/image identity
  and order, visible fill, transforms, opacity, blend/sampler state, UVs,
  indices, and final positions;
- repeated modulo-three replacement where every selected start-state structural
  snapshot equals the independent official start oracle after poisoning prior
  animated/solver state, while file-read/decode/upload/acquire counters remain
  unchanged; and
- cleanup after each injected public construction stage.

If the private fixture is absent, the normal public suite may report a clearly
named skip. The readiness command must treat absence, SHA mismatch, or skip as
failure.

### macOS pixel gate

Capture through the actual public Naylib/Raylib adapter, not a substitute
software test backend unless WP0.3 selected that backend as the production
adapter. Use:

- 960 by 540 RGBA;
- background `[245, 247, 250, 255]`;
- centered contain-fit of the stable 500 by 500 artboard;
- `Timeline 1` on a clean scene;
- initial settle at time 0; and
- finite positive steps no greater than 0.1 that total exactly 2 seconds.

Treat the official ROI `(210, 0)-(749, 539)` as inclusive source notation and
normalize it to half-open pixel coordinates `[210, 750) x [0, 540)`. Require
every pixel outside that half-open ROI to equal the declared background within
one channel value; visible output or garbage outside it is a failure. Compare
inside it using all request thresholds:

Before comparison, hash the supplied reference PNGs and require the 0-second
file to equal
`ac3e882aee9eb8a9ec1f8786a6084160fe1002ee935a9289211130048d6d8cef`
and the 2-second file to equal
`f617ff1b0a89c16b09f3afb8c0e001d5158da7775b82c27d8faf66bc88e7f126`.
Reject swapped, stale, missing, wrong-dimension, wrong-color-mode, or
wrong-alpha-mode reference inputs before calculating metrics.

| Metric | Required result |
|---|---:|
| Foreground pixels | at least 256 |
| Foreground share of reference ROI | at least 0.5% |
| Foreground area / official foreground area | 0.75 through 1.25 |
| Pixels changed from actual 0-second to 2-second frame | at least 32 |
| Actual changed pixels / official 22,558 | at least 0.5 |
| Mean absolute RGBA channel error in ROI | at most 2 |
| Compared pixels with any channel delta over 16 | at most 1% |

The official hashes are evidence identifiers, not an expectation that the
Raylib PNG byte stream matches CoreGraphics byte-for-byte. Record actual frame
hashes and numeric metrics.

Apply the same full-frame/outside-ROI discipline and channel-error thresholds to
the pinned Gate 0 reference pairs for `Timeline 2` and `Timeline 3`. Their
reference manifests define timestamp, ROI, foreground count, and changed-pixel
denominator. All three animation comparisons are required for readiness.

For movement, use a padded canvas that prevents clipping. Compare all final
projected vertices and the complete foreground masks before/after translation:
each vertex delta must be `(100, 0)`, each foreground pixel must map to the
pixel exactly 100 columns right, and all vacated/unused pixels must be the
background. A matrix-only, bounding-box-only, or single-marker assertion is not
sufficient.

### Lifecycle and failure gate

Use both internal resource counters and the required macOS-native diagnostic
named below. The matrix includes:

| Failure point | Required observation |
|---|---|
| malformed/version-mismatched import | structured error; no definitions/resources retained |
| unresolved or unsupported reachable object | contextual type/key failure; no partial scene |
| any of 13 PNG decodes/uploads | failed asset id/name reported; earlier resources released once |
| scene clone/start-pose/settle | after each injected failure, old scene advances/draws identically to an untouched control from the pre-failure state |
| renderer/context creation | file data remains safely disposable; no graphics calls after failure |
| draw/capture/readback/write | resources remain valid until explicit shutdown; error is propagated |
| repeated explicit dispose | no-op or documented safe result, never double release |
| window close/Escape path | resources disposed before context; no crash or lingering process |

The fixed stress profile is 300 modulo-three selection cycles, 10,000 headless
advances, 600 rendered frames, and 50 repetitions per injected failure point.
Require exact baseline restoration for Spliney-owned object/byte/texture/buffer
counters after each batch, zero upward trend after warmup, a retained macOS
`leaks --atExit --` report with zero Spliney-attributable definitely-lost
allocations, a 120-second harness timeout, and process exit within five seconds
of window close. Any substituted native diagnostic must be named and approved
in the readiness record before the run.

## Proposed canonical commands

Finalize exact filenames in Gate 0, but preserve these four separately visible
gates:

```bash
nimble test

nim c -r --hints:off --mm:orc \
  tests/integration/test_goblin_headless.nim -- \
  --asset /absolute/path/g0bl1ntest.riv \
  --require-private-fixture

nim c -r --hints:off --mm:orc -d:useNaylib \
  tests/integration/test_goblin_macos_capture.nim -- \
  --asset /absolute/path/g0bl1ntest.riv \
  --reference-dir /absolute/path/reference \
  --output-dir build/goblin-capture \
  --require-private-fixture

tools/verify-clean-checkout.sh \
  --asset /absolute/path/g0bl1ntest.riv \
  --reference-dir /absolute/path/reference
```

No script may infer the private asset from `~/Downloads`, silently fetch the
official runtime, or succeed when the private gate skipped.

## Readiness record schema

Commit a human-readable report plus machine-readable JSON containing:

- asset SHA and byte length;
- tested Spliney source SHA, official-runtime SHA, sibling demo SHA, and hashes
  of every probe/oracle source and generated manifest;
- OS/architecture, Nim/Nimble, Apple Clang, Naylib/Raylib, and every dependency
  revision/version;
- memory manager, compile definitions, native link inputs, and resolved
  dependency graph;
- commands, exit codes, test counts, skips, and relevant output hashes;
- importer inventory and unsupported/inert diagnostic list;
- intermediate bone/vertex oracle comparison metrics;
- capture dimensions/background/ROI/timestamps/step sequence/alpha mode;
- actual and reference frame hashes plus every pixel metric;
- lifecycle/failure-injection counts and diagnostic tool results; and
- dirty/clean checkout status and the tested source revision.

Avoid a self-referential report commit. Run all gates against an immutable clean
source commit, then commit only the generated readiness report in a separate
evidence-carrier commit whose parent is that tested source commit. The report
stores the tested source SHA and evidence inputs, not its own unknowable commit
SHA. The handoff message/tag records the evidence-carrier SHA after commit and
verifies that its only source-relative change is the readiness evidence.

Generated/private captures may remain ignored, but the record must identify
them strongly enough to reproduce and audit the passing run.

## Exception policy

Only the two final pixel-difference thresholds may receive the narrow exception
allowed by the request. The record must name approver, date, both actual frame
hashes, observed metrics, backend/host details, and a concrete repeatable
antialiasing reason. The non-empty and changed-frame gates remain mandatory.
No implementer may silently widen a threshold in test code.
