# Implementation and readiness tools

`run_generate_rive_registry.sh` pins the official runtime and regenerates the
complete type/property metadata and CoreRegistry factory skeleton from all 353
`dev/defs` JSON files. It rejects key/name collisions and inheritance errors,
runs twice for determinism, and supports a fail-closed committed-output check:

```bash
tools/run_generate_rive_registry.sh \
  --runtime /absolute/path/rive-runtime \
  --output src/spliney/generated/wire_registry.nim \
  --check
```

`run_rive_wire_audit.sh` is the non-shipping Gate 0 wire probe. It validates
the explicit private asset path and official runtime checkout against their
pins, reads the complete property schema from that checkout, and emits a
deterministic JSON record of every serialized object and property. Embedded
payload bytes are never written to the report; byte values are represented by
length and safe image metadata only.

Run it with explicit inputs:

```bash
tools/run_rive_wire_audit.sh \
  --asset /absolute/path/g0bl1ntest.riv \
  --runtime /absolute/path/rive-runtime \
  --output build/private-evidence/goblin-wire-audit.json
```

The generated private-fixture audit stays under the ignored `build/` tree.
Only redistributable summary manifests and their hashes may be committed.

`verify_rive_wire_loader.nim` compares the shipping bounds-checked loader's
entire flat stream against the private Gate 0 audit, including every byte
offset, type, property, wire kind, non-byte value, and embedded byte length:

```bash
nim c -r --hints:off --mm:orc --outdir:build \
  tools/verify_rive_wire_loader.nim -- \
  --asset /absolute/path/g0bl1ntest.riv \
  --audit build/private-evidence/goblin-wire-audit.json
```

`run_rive_oracle_probe.sh` builds an isolated copy of the pinned official
runtime and records full dynamic state for all three animations: bone/root-bone
matrices, constraint inputs and outputs, every reachable animated property,
visible fill state, complete textured-mesh draw buffers, and both bounded-step
and single-advance CoreGraphics frames. For downstream private tests it also
exports the original 13 embedded PNG payloads and an isolated CoreGraphics
rendering of one representative exact-asset image mesh. It runs twice and
requires every JSON and PNG byte to match. Its inputs are also explicit:

```bash
tools/run_rive_oracle_probe.sh \
  --asset /absolute/path/g0bl1ntest.riv \
  --runtime /absolute/path/rive-runtime \
  --output-dir build/private-evidence/goblin-oracle
```

`run_raylib_render_spike.sh` is the macOS Gate 0 renderer decision experiment.
It consumes only those explicit private oracle outputs, renders both known RGBA
pixels and the isolated exact-asset mesh through Naylib/rlgl, enforces the fixed
ADR 0002 metrics, and byte-compares two finite runs:

```bash
tools/run_raylib_render_spike.sh \
  --oracle build/private-evidence/goblin-oracle/first/oracle.json \
  --reference-dir build/private-evidence/goblin-oracle/first/reference \
  --output-dir build/private-evidence/raylib-render-spike
```

`run_raylib_png_decode_probe.sh` proves ADR 0003's split resource stages. It
decodes and normalizes all 13 private embedded payloads twice without creating
a window, byte-compares the RGBA8 outputs, checks corrupt-input error mapping,
then verifies that the retained CPU images upload after context creation:

```bash
tools/run_raylib_png_decode_probe.sh \
  --oracle build/private-evidence/goblin-oracle/first/oracle.json \
  --reference-dir build/private-evidence/goblin-oracle/first/reference \
  --output-dir build/private-evidence/raylib-png-decode
```

After both probes, enforce the complete Gate 0 evidence floor with:

```bash
nim c -r --hints:off --mm:orc tools/verify_goblin_gate0.nim -- \
  --wire:build/private-evidence/goblin-wire-audit.json \
  --oracle:build/private-evidence/goblin-oracle/first/oracle.json \
  --baseline:/absolute/path/spliney-goblin-demo/docs/asset-manifest.json
```

`run_exact_raylib_capture.sh` is the Gate 4 public-facade macOS capture. It
requires the exact private asset and pinned Gate 0 oracle outputs, builds the
opt-in Naylib adapter with ORC, renders both required states for all three
animations, and enforces the full pixel and 100-pixel translation policy. The
script runs the finite harness twice and requires every emitted PNG and JSON
byte to match:

```bash
tools/run_exact_raylib_capture.sh \
  --asset /absolute/path/g0bl1ntest.riv \
  --oracle build/private-evidence/goblin-oracle/first/oracle.json \
  --reference-dir build/private-evidence/goblin-oracle/first/reference \
  --output-dir build/private-evidence/exact-raylib-capture
```

The adapter is intentionally not exported by the core `spliney` barrel. A
Naylib consumer opts in with `-d:useNaylib`, imports
`spliney/backends/raylib/renderer`, initializes its Raylib window before
preparing images, and closes prepared resources before closing the window.

`run_exact_headless_gate.sh` is the fail-closed private-fixture headless gate.
It verifies both private inputs by SHA-256, runs the public inventory,
independent-scene, finite-playback, draw-stream, and transactional reselection
checks, then compares every numeric and draw-list oracle field:

```bash
tools/run_exact_headless_gate.sh \
  --asset /absolute/path/g0bl1ntest.riv \
  --oracle build/private-evidence/goblin-oracle/first/oracle.json
```

The ordinary `nimble test` invocation runs the same integration executable
without private inputs and prints a named skip. The readiness wrapper never
allows a missing fixture or oracle to become a skip.

`run_exact_lifecycle.sh` runs the fixed Gate 5 failure and stress matrix using
the real private asset and macOS graphics context. It builds with ORC and the
pinned Naylib revision, applies a 120-second watchdog to both runs, and retains
the deterministic metrics plus Apple `leaks --atExit` output:

```bash
tools/run_exact_lifecycle.sh \
  --asset /absolute/path/g0bl1ntest.riv \
  --output-dir build/private-evidence/exact-lifecycle
```

The leaks invocation excludes only the macOS AppIntents
`-[LNProcessInstanceRegistryClient makeXPCConnection]` root cycle. The wrapper
fails if any non-excluded stack remains, if the instrumented workload does not
finish, or if its metrics differ from the normal run.
