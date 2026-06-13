## Smoke test — proves the package imports and the toolchain (nim.cfg --path:src,
## --mm:orc) resolves intra-package imports. Real test suites live alongside each
## module (tests/io, tests/core, tests/scene, ...) as the beads are worked.

import std/unittest
import spliney

suite "smoke":
  test "package imports and reports its version":
    check splineyVersionString() == "0.1.0"
