# macOS Rive character demo capability request

This request describes the Spliney capabilities needed by the standalone
`spliney-goblin-demo` consumer. It is deliberately solution-neutral: it defines
the asset evidence, current gaps, observable consumer behavior, and proof of
readiness without choosing Spliney's internal architecture, file organization,
algorithms, or implementation sequence.

Read the documents in order:

| File | Purpose |
|---|---|
| [00-context-and-outcome.md](00-context-and-outcome.md) | Consumer goal, evidence sources, and desired outcome. |
| [01-evidence-and-current-gaps.md](01-evidence-and-current-gaps.md) | Exact asset inventory and the gaps observed in Spliney. |
| [02-required-capabilities.md](02-required-capabilities.md) | Runtime and rendering behavior the consumer needs. |
| [03-consumer-contract.md](03-consumer-contract.md) | Public interaction and lifecycle semantics needed by the demo. |
| [04-verification-and-evidence.md](04-verification-and-evidence.md) | Evidence that would demonstrate readiness. |
| [05-scope-and-readiness.md](05-scope-and-readiness.md) | Scope boundaries and the handoff condition back to the demo. |

The authoritative consumer-side evidence currently lives at:

- `/Users/punk1290/git/spliney-goblin-demo/docs/asset-manifest.json`
- `/Users/punk1290/git/spliney-goblin-demo/docs/asset-manifest.md`
- `/Users/punk1290/git/spliney-goblin-demo/docs/spliney-consumer-manifest.md`
- `/Users/punk1290/git/spliney-goblin-demo/tools/rive_asset_probe/`

The user-supplied asset is
`/Users/punk1290/Downloads/g0bl1ntest.riv`, SHA-256
`7a2f1d58da22e12932e73e76366b48651e66d9980153ece5433188c8fd08bc35`.
Its redistribution rights have not been established, so this request does not
ask for the asset or derived reference images to be committed to Spliney.
