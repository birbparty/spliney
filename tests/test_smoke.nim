## Smoke test — proves the package imports and the toolchain (nim.cfg --path:src,
## --mm:orc) resolves intra-package imports. Real test suites live alongside each
## module (tests/io, tests/core, tests/scene, ...) as the beads are worked.

import std/unittest
import spliney
import spliney/io/format

suite "smoke":
  test "package imports and reports its version":
    check splineyVersionString() == "0.1.0"

  test "wire format constants match the pinned official runtime":
    check RiveFormatFingerprint == "RIVE"
    check RiveFormatMajorVersion == 7'u64
    check TocPropertiesPerWord == 4
    check ord(WireFieldKind.uintOrBool) == 0
    check ord(WireFieldKind.string) == 1
    check ord(WireFieldKind.float32) == 2
    check ord(WireFieldKind.color) == 3
