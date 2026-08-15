## Bounds-checked Rive header, ToC, and flat object-stream loader.

import std/[math, sets, tables]

import spliney/errors
import spliney/generated/wire_registry
import spliney/io/format

type
  LoaderLimits* = object
    maxInputBytes*: int
    maxTocProperties*: int
    maxObjects*: int
    maxPropertiesPerObject*: int
    maxValueBytes*: int
    maxTotalValueBytes*: int

  TocEntry* = object
    propertyKey*: uint32
    backingCode*: uint8

  WireValue* = object
    kind*: WireKind
    uintValue*: uint64
    floatValue*: float32
    colorValue*: uint32
    dataValue*: string

  WireProperty* = object
    key*: uint32
    byteOffset*: uint64
    value*: WireValue

  WireObject* = object
    typeKey*: uint32
    byteOffset*: uint64
    knownType*: bool
    properties*: seq[WireProperty]

  WirePropertyLookup* = object
    found*: bool
    serialized*: bool
    value*: WireValue
    defaultText*: string

  WireFile* = ref object
    sourceBytes*: seq[byte]
    major*: uint64
    minor*: uint64
    fileId*: uint64
    toc*: seq[TocEntry]
    objects*: seq[WireObject]

  WireReader = object
    data: string
    offset: int
    limits: LoaderLimits
    totalValueBytes: int
    label: string

  ParseFailure = object of CatchableError
    error: SplineyError

proc defaultLoaderLimits*(): LoaderLimits =
  LoaderLimits(
    maxInputBytes: 64 * 1024 * 1024,
    maxTocProperties: 16 * 1024,
    maxObjects: 1_000_000,
    maxPropertiesPerObject: 16 * 1024,
    maxValueBytes: 32 * 1024 * 1024,
    maxTotalValueBytes: 64 * 1024 * 1024)

proc parseError(reader: WireReader; stage: ErrorStage; message: string;
    offset = -1; typeKey = -1'i32; propertyKey = -1'i32;
    category = ErrorCategory.malformedData): ref ParseFailure =
  result = newException(ParseFailure, message)
  result.error = SplineyError(
    category: category,
    stage: stage,
    message: message,
    context: ErrorContext(
      label: reader.label,
      objectTypeKey: typeKey,
      propertyKey: propertyKey,
      assetId: -1,
      animationIndex: -1,
      hasByteOffset: true,
      byteOffset: uint64(if offset >= 0: offset else: reader.offset)))

proc require(reader: WireReader; count: int; stage: ErrorStage) =
  if count < 0 or reader.offset > reader.data.len - count:
    raise reader.parseError(stage, "truncated Rive input")

proc readByte(reader: var WireReader; stage: ErrorStage): uint8 =
  reader.require(1, stage)
  result = uint8(reader.data[reader.offset])
  inc reader.offset

proc readVarUint(reader: var WireReader; stage: ErrorStage): uint64 =
  let start = reader.offset
  for index in 0 .. 9:
    let value = reader.readByte(stage)
    if index == 9 and (value and 0xfe'u8) != 0:
      raise reader.parseError(stage, "varuint exceeds 64 bits", start)
    result = result or (uint64(value and 0x7f'u8) shl (index * 7))
    if (value and 0x80'u8) == 0:
      if index > 0 and (value and 0x7f'u8) == 0:
        raise reader.parseError(stage, "non-canonical varuint", start)
      return
  raise reader.parseError(stage, "unterminated varuint", start)

proc readUint32Le(reader: var WireReader; stage: ErrorStage): uint32 =
  reader.require(4, stage)
  for shift in countup(0, 24, 8):
    result = result or (uint32(reader.readByte(stage)) shl shift)

proc readFloat32Le(reader: var WireReader; stage: ErrorStage): float32 =
  cast[float32](reader.readUint32Le(stage))

proc readData(reader: var WireReader; stage: ErrorStage): string =
  let start = reader.offset
  let lengthValue = reader.readVarUint(stage)
  if lengthValue > uint64(high(int)) or
      lengthValue > uint64(reader.limits.maxValueBytes):
    raise reader.parseError(stage, "Rive value length exceeds limit", start)
  let length = int(lengthValue)
  if reader.totalValueBytes > reader.limits.maxTotalValueBytes - length:
    raise reader.parseError(stage, "total Rive value bytes exceed limit", start)
  reader.require(length, stage)
  result = reader.data[reader.offset ..< reader.offset + length]
  reader.offset += length
  reader.totalValueBytes += length

proc valueFor(reader: var WireReader; kind: WireKind): WireValue =
  result.kind = kind
  case kind
  of WireKind.uintValue:
    result.uintValue = reader.readVarUint(ErrorStage.objectStream)
  of WireKind.stringValue, WireKind.bytesValue:
    result.dataValue = reader.readData(ErrorStage.objectStream)
  of WireKind.floatValue:
    result.floatValue = reader.readFloat32Le(ErrorStage.objectStream)
    if classify(result.floatValue) in {fcNan, fcInf, fcNegInf}:
      raise reader.parseError(ErrorStage.objectStream,
        "non-finite serialized float")
  of WireKind.colorValue:
    result.colorValue = reader.readUint32Le(ErrorStage.objectStream)

proc tocWireKind(code: uint8): WireKind =
  case code
  of 0: WireKind.uintValue
  of 1: WireKind.stringValue
  of 2: WireKind.floatValue
  of 3: WireKind.colorValue
  else: raise newException(Defect, "unreachable ToC backing code")

proc loadRiveWire*(bytes: openArray[byte]; label = "<memory>";
    limits = defaultLoaderLimits()): SplineyResult[WireFile] =
  var reader = WireReader(limits: limits, label: label)
  if bytes.len > limits.maxInputBytes:
    return err[WireFile](SplineyError(
      category: ErrorCategory.malformedData,
      stage: ErrorStage.header,
      message: "Rive input exceeds size limit",
      context: ErrorContext(label: label, objectTypeKey: -1, propertyKey: -1,
        assetId: -1, animationIndex: -1, hasByteOffset: true, byteOffset: 0)))
  reader.data = newString(bytes.len)
  if bytes.len > 0:
    copyMem(addr reader.data[0], unsafeAddr bytes[0], bytes.len)

  try:
    reader.require(RiveFormatFingerprint.len, ErrorStage.header)
    if reader.data[0 ..< RiveFormatFingerprint.len] != RiveFormatFingerprint:
      raise reader.parseError(ErrorStage.header, "invalid Rive fingerprint", 0)
    reader.offset = RiveFormatFingerprint.len
    let major = reader.readVarUint(ErrorStage.header)
    if major != RiveFormatMajorVersion:
      raise reader.parseError(ErrorStage.header, "unsupported Rive major version",
        category = ErrorCategory.incompatibleFormat)
    let minor = reader.readVarUint(ErrorStage.header)
    let fileId = reader.readVarUint(ErrorStage.header)

    var tocKeys: seq[uint32]
    while true:
      let keyValue = reader.readVarUint(ErrorStage.tableOfContents)
      if keyValue == 0: break
      if keyValue > high(uint32).uint64:
        raise reader.parseError(ErrorStage.tableOfContents,
          "ToC property key exceeds uint32")
      if tocKeys.len >= limits.maxTocProperties:
        raise reader.parseError(ErrorStage.tableOfContents,
          "ToC property count exceeds limit")
      let key = keyValue.uint32
      if key in tocKeys:
        raise reader.parseError(ErrorStage.tableOfContents,
          "duplicate ToC property key")
      tocKeys.add key

    var tocKinds = initTable[uint32, uint8]()
    var toc: seq[TocEntry]
    for base in countup(0, tocKeys.high, TocPropertiesPerWord):
      let packed = reader.readUint32Le(ErrorStage.tableOfContents)
      for slot in 0 ..< min(TocPropertiesPerWord, tocKeys.len - base):
        let code = uint8((packed shr (slot * TocBitsPerProperty)) and
          TocBackingTypeMask.uint32)
        tocKinds[tocKeys[base + slot]] = code
        toc.add TocEntry(propertyKey: tocKeys[base + slot], backingCode: code)

    var objects: seq[WireObject]
    while reader.offset < reader.data.len:
      if objects.len >= limits.maxObjects:
        raise reader.parseError(ErrorStage.objectStream,
          "object count exceeds limit")
      let objectOffset = reader.offset
      let typeValue = reader.readVarUint(ErrorStage.objectStream)
      if typeValue == 0 or typeValue > high(uint32).uint64:
        raise reader.parseError(ErrorStage.objectStream,
          "invalid object type key", objectOffset)
      let typeKey = typeValue.uint32
      var item = WireObject(
        typeKey: typeKey,
        byteOffset: objectOffset.uint64,
        knownType: not typeMetadata(typeKey).isNil)
      var seenProperties = initHashSet[uint32]()
      while true:
        let propertyOffset = reader.offset
        let keyValue = reader.readVarUint(ErrorStage.objectStream)
        if keyValue == 0: break
        if keyValue > high(uint32).uint64:
          raise reader.parseError(ErrorStage.objectStream,
            "property key exceeds uint32", propertyOffset, typeKey.int32)
        if item.properties.len >= limits.maxPropertiesPerObject:
          raise reader.parseError(ErrorStage.objectStream,
            "property count exceeds per-object limit", propertyOffset,
            typeKey.int32)
        let key = keyValue.uint32
        if key in seenProperties:
          raise reader.parseError(ErrorStage.objectStream,
            "duplicate serialized property", propertyOffset, typeKey.int32,
            key.int32)
        seenProperties.incl key
        let metadata = propertyMetadata(key)
        var kind: WireKind
        if not metadata.isNil:
          kind = metadata.wireKind
        elif tocKinds.hasKey(key):
          kind = tocWireKind(tocKinds[key])
        else:
          raise reader.parseError(ErrorStage.objectStream,
            "unknown property is absent from ToC", propertyOffset,
            typeKey.int32, key.int32)
        item.properties.add WireProperty(
          key: key,
          byteOffset: propertyOffset.uint64,
          value: reader.valueFor(kind))
      objects.add move(item)

    var file = WireFile(
      major: major,
      minor: minor,
      fileId: fileId,
      toc: move(toc),
      objects: move(objects),
      sourceBytes: newSeq[byte](bytes.len))
    if bytes.len > 0:
      copyMem(addr file.sourceBytes[0], unsafeAddr bytes[0], bytes.len)
    ok(file)
  except ParseFailure as failure:
    err[WireFile](failure.error)

proc serializedProperty*(item: WireObject; key: uint32): ptr WireProperty =
  for property in item.properties:
    if property.key == key: return unsafeAddr property

proc runtimeDefaultText*(key: uint32): string =
  let metadata = propertyMetadata(key)
  if metadata.isNil: return ""
  if metadata.initialValueRuntime.len > 0: metadata.initialValueRuntime
  else: metadata.initialValue

proc propertyOrDefault*(item: WireObject; key: uint32): WirePropertyLookup =
  let serialized = item.serializedProperty(key)
  if not serialized.isNil:
    return WirePropertyLookup(
      found: true,
      serialized: true,
      value: serialized.value)
  let metadata = propertyMetadata(key)
  if metadata.isNil: return
  WirePropertyLookup(
    found: true,
    serialized: false,
    value: WireValue(kind: metadata.wireKind),
    defaultText: runtimeDefaultText(key))
