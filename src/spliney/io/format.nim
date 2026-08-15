## Stable wire-format constants grounded against the pinned official runtime.

const
  RiveFormatMajorVersion* = 7'u64
    ## Major version accepted by this implementation. Grounded against
    ## rive::File::majorVersion in include/rive/file.hpp at runtime commit
    ## 372b8092e940f32cf84499ae23a4899ec66a9ab1.

  RiveFormatFingerprint* = "RIVE"
    ## Four-byte file fingerprint from include/rive/runtime_header.hpp.

  TocPropertiesPerWord* = 4
    ## The runtime reads a new uint32 after four 2-bit ToC entries. Only the
    ## low eight bits of each word carry field codes.

type WireFieldKind* {.pure.} = enum
  ## Forward-compatibility field codes from RuntimeHeader::read and the core
  ## field types at the pinned official runtime revision.
  uintOrBool = 0
  string = 1
  float32 = 2
  color = 3
