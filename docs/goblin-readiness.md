# macOS goblin demo readiness

Status: **ready**. All planned Gates 0 through 5 and the clean external-consumer
handoff passed on macOS against immutable Spliney source commit
`08c9abf6318291ca720895891235780b9153311f`.

The machine-readable evidence is
[goblin-readiness.json](evidence/goblin-readiness.json). Private asset bytes,
official reference images, captures, and leaks output remain outside Git; the
JSON pins their hashes and the source used to produce them.

## What passed

- A detached clean clone with an empty Nimble package cache reproduced the
  package checks and 63 ordinary tests. The one ordinary-suite skip was the
  intentionally absent private fixture; the explicit readiness gates ran with
  the fixture and had zero skips.
- Gate 0 matched 525 wire objects, 1,531 properties, 13 embedded PNGs, three
  animations, six bone/root transforms, three constraints, and 107 deformed
  vertices against the pinned official runtime oracle.
- The public headless path exercised all three animations, complete draw lists,
  bounded stepping, independent scenes, and 30 poisoned transactional
  replacements without rereading or repreparing the asset.
- The real Naylib/Raylib adapter decoded and uploaded all 13 images and rendered
  every frame pair through direct `rlgl` textured triangles. Both capture runs
  were byte-identical. All per-frame mean RGBA errors were below `0.315`, all
  outside-ROI errors were zero, and no threshold exception was used.
- A padded-canvas comparison proved that every projected vertex and foreground
  pixel moved exactly 100 pixels right, with all vacated pixels restored to the
  background.
- The lifecycle matrix covered 50 repetitions at every failure point, 300
  animation selections, 10,000 headless advances, and 600 real GPU frames.
  Every owned-resource counter returned to baseline. Apple `leaks --atExit`
  printed no non-excluded stack and found no Spliney-attributable definitely
  lost allocation.
- A separate Nimble package copied outside the repository compiled with only
  public Spliney imports, opened a real Raylib context, rendered ten frames from
  each animation, and shut down in the documented order.

## Pinned handoff

Use Spliney commit `08c9abf6318291ca720895891235780b9153311f` with:

- Nim 2.2.10 and Nimble 0.22.2;
- ORC memory management and the C backend;
- Naylib 26.08.0 revision
  `19dd4e7e34c705c677e89b3a6516846c9f2e0125`, aggregate SHA-256
  `a705b3fc7987785b6609780a0237e92f380705a357faee8a30af8b26275dc1ae`;
- Naylib's bundled Raylib 5.6-dev; and
- `-d:useNaylib --noNimblePath` plus explicit Spliney `src` and Naylib paths.

The consumer-facing API and shutdown sequence are documented in
[macos-goblin-consumer.md](macos-goblin-consumer.md). The executable reference
package is in [`tests/consumer/goblin_demo`](../tests/consumer/goblin_demo).

The tested external lifecycle is:

1. import the Rive file and inspect the returned result;
2. initialize the Raylib window;
3. prepare image/GPU resources;
4. create and initially settle a scene;
5. advance by finite positive steps no larger than 0.1 seconds and draw through
   the public adapter;
6. dispose scenes and render targets, then prepared resources;
7. close the Raylib window; and
8. close the imported file.

State machines are retained metadata but are not played by this linear
animation slice. Nested artboards, clipping, text, audio, scripting, general
path tessellation, console rendering, and Boxy remain outside this milestone.

## Reproduce

From a clean checkout at the tested commit, provide the pinned private inputs
explicitly and run:

```bash
./tools/verify_clean_checkout.sh \
  --asset /absolute/path/g0bl1ntest.riv \
  --wire-audit /absolute/path/goblin-wire-audit.json \
  --oracle /absolute/path/oracle.json \
  --reference-dir /absolute/path/reference \
  --baseline /absolute/path/spliney-goblin-demo/docs/asset-manifest.json \
  --naylib-dir /absolute/path/naylib-26.08.0-19dd4e7e \
  --output-dir build/private-evidence/clean-checkout
```

The command validates every input pin, clones the source commit locally,
prevents global Nimble package resolution, runs every gate, builds the public
consumer outside the checkout, and fails if the detached clone becomes dirty.
