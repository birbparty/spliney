## Compare the shipping loader's complete flat stream with Gate 0 private audit.

import std/[json, os]

import spliney/generated/wire_registry
import spliney/io/loader

proc usage() =
  stderr.writeLine "usage: verify_rive_wire_loader --asset FILE --audit FILE"

proc arguments(): tuple[asset, audit: string] =
  let values = commandLineParams()
  var index = 0
  while index < values.len:
    if values[index] == "--":
      inc index
      continue
    if index + 1 >= values.len:
      usage()
      quit 2
    case values[index]
    of "--asset": result.asset = values[index + 1]
    of "--audit": result.audit = values[index + 1]
    else:
      usage()
      quit 2
    index += 2
  if result.asset.len == 0 or result.audit.len == 0:
    usage()
    quit 2

proc expectedKind(kind: WireKind): string =
  case kind
  of WireKind.uintValue: "uint"
  of WireKind.stringValue: "string"
  of WireKind.floatValue: "float"
  of WireKind.colorValue: "color"
  of WireKind.bytesValue: "bytes"

proc main() =
  let paths = arguments()
  let raw = readFile(paths.asset)
  let loaded = loadRiveWire(raw.toOpenArrayByte(0, raw.high), paths.asset)
  if not loaded.isOk:
    stderr.writeLine loaded.error.message, " at ", loaded.error.context.byteOffset
    quit 3
  let audit = parseFile(paths.audit)
  doAssert loaded.value.major == audit["asset"]["major"].getBiggestInt.uint64
  doAssert loaded.value.minor == audit["asset"]["minor"].getBiggestInt.uint64
  doAssert loaded.value.fileId == audit["asset"]["fileId"].getBiggestInt.uint64
  doAssert loaded.value.objects.len == audit["objects"].len

  var propertyCount = 0
  var expectedPropertyCount = 0
  for index, item in loaded.value.objects:
    let expected = audit["objects"][index]
    doAssert item.byteOffset == expected["byteOffset"].getBiggestInt.uint64
    doAssert item.typeKey == expected["typeKey"].getBiggestInt.uint32
    doAssert item.knownType
    doAssert item.properties.len == expected["properties"].len
    expectedPropertyCount += expected["properties"].len
    for propertyIndex, property in item.properties:
      inc propertyCount
      let expectedProperty = expected["properties"][propertyIndex]
      doAssert property.byteOffset ==
        expectedProperty["byteOffset"].getBiggestInt.uint64
      doAssert property.key ==
        expectedProperty["propertyKey"].getBiggestInt.uint32
      doAssert property.value.kind.expectedKind ==
        expectedProperty["wireKind"].getStr
      case property.value.kind
      of WireKind.uintValue:
        doAssert $property.value.uintValue == $expectedProperty["value"]
      of WireKind.stringValue:
        doAssert property.value.dataValue == expectedProperty["value"].getStr
      of WireKind.floatValue:
        let expectedFloat = expectedProperty["value"].getFloat
        doAssert abs(property.value.floatValue.float64 - expectedFloat) <=
          max(0.000001, abs(expectedFloat) * 0.000001)
      of WireKind.colorValue:
        doAssert property.value.colorValue.uint64 ==
          expectedProperty["value"].getBiggestInt.uint64
      of WireKind.bytesValue:
        doAssert property.value.dataValue.len ==
          expectedProperty["value"]["byteLength"].getInt

  doAssert propertyCount == expectedPropertyCount
  echo "shipping loader verified: ", loaded.value.objects.len,
    " objects, ", propertyCount, " properties, ", loaded.value.sourceBytes.len,
    " owned source bytes"

when isMainModule:
  main()
