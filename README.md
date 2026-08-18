# Spliney

Spliney is a from-scratch Rive animation runtime for Nim. Its core imports
`.riv` files, creates independent linear-animation scenes, advances them with
bounded time steps, and emits backend-neutral drawing commands. The current
macOS adapter renders the project’s pinned textured goblin slice through
Naylib/Raylib.

## Package

Spliney 0.1.0 requires Nim 2 or newer, uses the C backend, and is tested with
ORC. The core package has no third-party dependency. From a source checkout:

```bash
nimble develop -y
nimble test -y
```

A dependent package can declare the eventual registry release in its Nimble
file:

```nim
requires "spliney >= 0.1.0"
```

For a sibling source checkout, compile with an explicit source path instead:

```bash
nim c --mm:orc --path:/absolute/path/spliney/src app.nim
```

Importing `spliney` is renderer-neutral and does not import Naylib or platform
graphics libraries:

```nim
import spliney

let loaded = loadRiveFile("character.riv", "character.riv")
if not loaded.isOk:
  quit loaded.error.message

let artboard = loaded.value.defaultArtboard()
if not artboard.isOk:
  quit artboard.error.message

echo artboard.value.name
```

Backend resources are prepared only after their graphics context exists.
Scenes and resources must be closed before the imported file, and GPU resources
must be closed before the window. All close operations are idempotent. See
[tools/README.md](tools/README.md) for the explicit private-fixture readiness
commands and [ADR 0001](docs/adr/0001-public-api-and-lifetimes.md) for the full
ownership/error contract.

The complete initialization, per-frame, animation-selection, error, and
shutdown recipe is in
[the macOS consumer contract](docs/macos-goblin-consumer.md).

The exact macOS adapter is opt-in: add `-d:useNaylib`, provide the pinned Naylib
source with an explicit compiler path, and import
`spliney/backends/raylib/renderer`. Naylib is deliberately not a transitive
dependency of the renderer-neutral package.
