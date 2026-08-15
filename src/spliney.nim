## spliney — a from-scratch Rive animation runtime in Nim.
##
## This is the package barrel module. Implementation lives under `src/spliney/`:
## the renderer-agnostic core (binary `.riv` loader → core object model →
## scene-graph dependency solver → linear-animation + state-machine engine,
## emitting draw commands against an abstract `Renderer`/`Factory` seam) plus
## thin boxy and clckr/raylib render adapters.
##
## Design reference: `docs/reference/rive-runtime-reference.md`.
## Task graph: `bd ready` (Beads).

import spliney/contracts

export contracts

const splineyVersion* = "0.1.0"
  ## The spliney runtime version. Keep in sync with `spliney.nimble`.

proc splineyVersionString*(): string =
  ## Returns the spliney runtime version string.
  splineyVersion
