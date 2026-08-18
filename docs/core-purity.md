# Core dependency purity

Spliney’s renderer-neutral source is allowed to import only:

- Nim `std/*` modules;
- other `spliney/*` modules; and
- the reserved portable math dependencies `vmath` and `bumpy`.

The complete pure-module inventory is fixed in
`tests/purity/test_core_imports.nim`. It includes the root `spliney` barrel,
contracts, loader/generated metadata, math, animation, transform, scene,
render protocol, and the dependency-free recording backend.

These two opt-in modules are deliberately outside the pure inventory:

- `spliney/adapters/raylib_images.nim`
- `spliney/backends/raylib/renderer.nim`

The test is fail-closed: a new source module, a new adapter, an unrecognized
import form, or any dependency outside the allowlist fails until the inventory
and policy are reviewed together. It also compiles the public consumer with
`--noNimblePath`, proving that importing `spliney` cannot resolve an accidental
graphics package from the user cache.
