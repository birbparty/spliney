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
