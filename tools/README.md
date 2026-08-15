# Implementation and readiness tools

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
and single-advance CoreGraphics frames. It runs twice and requires every JSON
and PNG byte to match. Its inputs are also explicit:

```bash
tools/run_rive_oracle_probe.sh \
  --asset /absolute/path/g0bl1ntest.riv \
  --runtime /absolute/path/rive-runtime \
  --output-dir build/private-evidence/goblin-oracle
```

After both probes, enforce the complete Gate 0 evidence floor with:

```bash
nim c -r --hints:off --mm:orc tools/verify_goblin_gate0.nim -- \
  --wire:build/private-evidence/goblin-wire-audit.json \
  --oracle:build/private-evidence/goblin-oracle/first/oracle.json \
  --baseline:/absolute/path/spliney-goblin-demo/docs/asset-manifest.json
```
