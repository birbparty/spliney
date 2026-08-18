import std/unittest

import spliney/errors
import spliney/generated/wire_registry
import spliney/io/loader

proc addVarUint(data: var seq[byte], value: uint64) =
  var remaining = value
  while remaining >= 0x80:
    data.add byte((remaining and 0x7f) or 0x80)
    remaining = remaining shr 7
  data.add byte(remaining)

proc addUint32(data: var seq[byte], value: uint32) =
  for shift in countup(0, 24, 8):
    data.add byte((value shr shift) and 0xff)

proc addHeader(data: var seq[byte], major = 7'u64,
    toc: openArray[tuple[key: uint32, code: uint8]] = []) =
  for value in "RIVE": data.add byte(value)
  data.addVarUint major
  data.addVarUint 3
  data.addVarUint 42
  for entry in toc: data.addVarUint entry.key
  data.addVarUint 0
  for base in countup(0, toc.high, 4):
    var packed: uint32
    for slot in 0 ..< min(4, toc.len - base):
      packed = packed or (toc[base + slot].code.uint32 shl (slot * 2))
    data.addUint32 packed

proc minimalArtboard(): seq[byte] =
  result.addHeader()
  result.addVarUint 1
  result.addVarUint 11
  result.addUint32 cast[uint32](0.25'f32)
  result.addVarUint 0

suite "bounds-checked Rive wire loader":
  test "reads a known object and owns a source copy":
    var bytes = minimalArtboard()
    let loaded = loadRiveWire(bytes, "synthetic")
    require loaded.isOk
    check loaded.value.major == 7
    check loaded.value.minor == 3
    check loaded.value.fileId == 42
    check loaded.value.objects.len == 1
    check loaded.value.objects[0].knownType
    check loaded.value.objects[0].typeKey == 1
    let origin = loaded.value.objects[0].serializedProperty(11)
    require not origin.isNil
    check origin.value.kind == WireKind.floatValue
    check abs(origin.value.floatValue - 0.25) < 0.000001
    bytes[0] = 0
    check loaded.value.sourceBytes[0] == byte('R')

  test "uses ToC backing codes to retain unknown types and properties":
    var bytes: seq[byte]
    bytes.addHeader(toc = [(key: 2000'u32, code: 1'u8)])
    bytes.addVarUint 5000
    bytes.addVarUint 2000
    bytes.addVarUint 3
    for value in "abc": bytes.add byte(value)
    bytes.addVarUint 0
    let loaded = loadRiveWire(bytes)
    require loaded.isOk
    check not loaded.value.objects[0].knownType
    check loaded.value.toc == @[
      TocEntry(propertyKey: 2000, backingCode: 1)]
    let unknown = loaded.value.objects[0].serializedProperty(2000)
    require not unknown.isNil
    check unknown.value.kind == WireKind.stringValue
    check unknown.value.dataValue == "abc"

  test "preserves known embedded byte payloads":
    var bytes: seq[byte]
    bytes.addHeader()
    bytes.addVarUint 106
    bytes.addVarUint 212
    bytes.addVarUint 4
    bytes.add @[0'u8, 1, 2, 255]
    bytes.addVarUint 0
    let loaded = loadRiveWire(bytes)
    require loaded.isOk
    let contents = loaded.value.objects[0].serializedProperty(212)
    require not contents.isNil
    check contents.value.kind == WireKind.bytesValue
    check contents.value.dataValue.len == 4
    check uint8(contents.value.dataValue[3]) == 255

  test "reports every truncation with a typed byte offset":
    let complete = minimalArtboard()
    for length in 0 ..< complete.len:
      let loaded = loadRiveWire(complete[0 ..< length], "truncated")
      if loaded.isOk:
        check loaded.value.objects.len == 0
      else:
        check loaded.error.category == ErrorCategory.malformedData
        check loaded.error.context.label == "truncated"
        check loaded.error.context.hasByteOffset
        check loaded.error.context.byteOffset <= length.uint64

  test "distinguishes incompatible major and malformed headers":
    var incompatible: seq[byte]
    incompatible.addHeader(major = 8)
    let majorResult = loadRiveWire(incompatible)
    check not majorResult.isOk
    check majorResult.error.category == ErrorCategory.incompatibleFormat
    check majorResult.error.stage == ErrorStage.header

    var badMagic = minimalArtboard()
    badMagic[0] = byte('X')
    let magicResult = loadRiveWire(badMagic)
    check not magicResult.isOk
    check magicResult.error.category == ErrorCategory.malformedData
    check magicResult.error.context.byteOffset == 0

  test "rejects overflow noncanonical unknown and duplicate encodings":
    var overflow = @[byte('R'), byte('I'), byte('V'), byte('E')]
    for _ in 0 .. 9: overflow.add 0xff
    let overflowResult = loadRiveWire(overflow)
    check not overflowResult.isOk
    check overflowResult.error.message == "varuint exceeds 64 bits"

    var noncanonical = @[byte('R'), byte('I'), byte('V'), byte('E'),
      0x87'u8, 0'u8]
    let canonicalResult = loadRiveWire(noncanonical)
    check not canonicalResult.isOk
    check canonicalResult.error.message == "non-canonical varuint"

    var unknown: seq[byte]
    unknown.addHeader()
    unknown.addVarUint 1
    unknown.addVarUint 2000
    let unknownResult = loadRiveWire(unknown)
    check not unknownResult.isOk
    check unknownResult.error.context.propertyKey == 2000

    var duplicate: seq[byte]
    duplicate.addHeader(toc = [(key: 2000'u32, code: 0'u8)])
    duplicate.addVarUint 1
    duplicate.addVarUint 2000
    duplicate.addVarUint 1
    duplicate.addVarUint 2000
    duplicate.addVarUint 2
    duplicate.addVarUint 0
    let duplicateResult = loadRiveWire(duplicate)
    check not duplicateResult.isOk
    check duplicateResult.error.message == "duplicate serialized property"

  test "enforces allocation limits before reading values":
    var bytes: seq[byte]
    bytes.addHeader()
    bytes.addVarUint 106
    bytes.addVarUint 212
    bytes.addVarUint 5
    bytes.add @[1'u8, 2, 3, 4, 5]
    bytes.addVarUint 0
    var limits = defaultLoaderLimits()
    limits.maxValueBytes = 4
    let loaded = loadRiveWire(bytes, limits = limits)
    check not loaded.isOk
    check loaded.error.message == "Rive value length exceeds limit"

  test "exposes runtime defaults without evaluating generated expressions":
    check runtimeDefaultText(11) == "0"
    check runtimeDefaultText(236) == "-1"
    check runtimeDefaultText(high(uint32)) == ""
    let loaded = loadRiveWire(minimalArtboard())
    require loaded.isOk
    let serialized = loaded.value.objects[0].propertyOrDefault(11)
    check serialized.found
    check serialized.serialized
    check serialized.value.floatValue == 0.25
    let missing = loaded.value.objects[0].propertyOrDefault(236)
    check missing.found
    check not missing.serialized
    check missing.value.kind == WireKind.uintValue
    check missing.defaultText == "-1"
    check not loaded.value.objects[0].propertyOrDefault(high(uint32)).found
