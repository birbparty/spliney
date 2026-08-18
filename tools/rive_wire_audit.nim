## Non-shipping, deterministic wire audit for a pinned Rive runtime file.
##
## The audit deliberately reads property types from the pinned official
## dev/defs registry. It never imports the official runtime and never emits
## embedded asset bytes.

import std/[algorithm, json, os, parseopt, strformat, strutils, tables]

type
  ValueKind = enum
    vkUint = "uint"
    vkString = "string"
    vkFloat = "float"
    vkColor = "color"
    vkBytes = "bytes"

  TypeDef = object
    name: string
    source: string

  PropertyDef = object
    name: string
    schemaType: string
    runtimeType: string
    kind: ValueKind
    source: string

  WireReader = object
    data: string
    offset: int

  Options = object
    assetPath: string
    defsPath: string
    outputPath: string
    runtimeSha: string

proc fail(reader: WireReader; message: string): ref ValueError =
  newException(ValueError, &"{message} at byte offset {reader.offset}")

proc require(reader: WireReader; count: int) =
  if count < 0 or reader.offset > reader.data.len - count:
    raise reader.fail(&"truncated input while reading {count} bytes")

proc readByte(reader: var WireReader): uint8 =
  reader.require(1)
  result = uint8(reader.data[reader.offset])
  inc reader.offset

proc readVarUint(reader: var WireReader): uint64 =
  var shift = 0
  for index in 0 .. 9:
    let value = reader.readByte()
    if index == 9 and (value and 0xfe'u8) != 0:
      raise reader.fail("varuint exceeds 64 bits")
    result = result or (uint64(value and 0x7f'u8) shl shift)
    if (value and 0x80'u8) == 0:
      return
    shift += 7
  raise reader.fail("unterminated varuint")

proc readUint32Le(reader: var WireReader): uint32 =
  reader.require(4)
  for shift in countup(0, 24, 8):
    result = result or (uint32(reader.readByte()) shl shift)

proc readFloat32Le(reader: var WireReader): float32 =
  cast[float32](reader.readUint32Le())

proc readLength(reader: var WireReader): int =
  let value = reader.readVarUint()
  if value > uint64(high(int)):
    raise reader.fail("length exceeds host integer range")
  int(value)

proc readStringValue(reader: var WireReader): string =
  let length = reader.readLength()
  reader.require(length)
  result = reader.data[reader.offset ..< reader.offset + length]
  reader.offset += length

proc readBytesValue(reader: var WireReader): string =
  reader.readStringValue()

proc isRuntimeProperty(node: JsonNode): bool =
  not node.hasKey("runtime") or node["runtime"].getBool()

proc classifyProperty(node: JsonNode): tuple[
    schemaType: string, runtimeType: string, kind: ValueKind] =
  result.schemaType = node["type"].getStr()
  let runtimeType =
    if node.hasKey("typeRuntime"): node["typeRuntime"].getStr()
    else: result.schemaType
  result.runtimeType = runtimeType
  case runtimeType
  of "Bytes": result.kind = vkBytes
  of "String": result.kind = vkString
  of "double": result.kind = vkFloat
  of "Color": result.kind = vkColor
  else: result.kind = vkUint

proc loadDefs(defsPath: string): tuple[
    types: Table[uint64, TypeDef], properties: Table[uint64, PropertyDef]] =
  if not dirExists(defsPath):
    raise newException(ValueError, "defs directory does not exist: " & defsPath)

  var files: seq[string]
  for path in walkDirRec(defsPath):
    if path.endsWith(".json"):
      files.add(path)
  files.sort()

  for path in files:
    let document = parseFile(path)
    let source = relativePath(path, defsPath)
    if document.hasKey("key") and document["key"].hasKey("int"):
      let key = uint64(document["key"]["int"].getInt())
      let definition = TypeDef(name: document["name"].getStr(), source: source)
      if result.types.hasKey(key) and result.types[key] != definition:
        raise newException(ValueError, &"duplicate type key {key}")
      result.types[key] = definition

    if not document.hasKey("properties"):
      continue
    for name, node in document["properties"]:
      if not node.isRuntimeProperty() or not node.hasKey("key") or
          not node["key"].hasKey("int"):
        continue
      let key = uint64(node["key"]["int"].getInt())
      let classified = classifyProperty(node)
      let definition = PropertyDef(
        name: name,
        schemaType: classified.schemaType,
        runtimeType: classified.runtimeType,
        kind: classified.kind,
        source: source)
      if result.properties.hasKey(key) and result.properties[key] != definition:
        raise newException(ValueError, &"conflicting property key {key}")
      result.properties[key] = definition

proc pngMetadata(data: string): JsonNode =
  result = newJObject()
  let signature = "\x89PNG\x0d\x0a\x1a\x0a"
  result["isPng"] = %(data.len >= signature.len and
    data[0 ..< signature.len] == signature)
  if result["isPng"].getBool() and data.len >= 24:
    proc bigEndian32(start: int): uint32 =
      (uint32(uint8(data[start])) shl 24) or
      (uint32(uint8(data[start + 1])) shl 16) or
      (uint32(uint8(data[start + 2])) shl 8) or
      uint32(uint8(data[start + 3]))
    result["width"] = %bigEndian32(16)
    result["height"] = %bigEndian32(20)

proc propertyValue(reader: var WireReader; kind: ValueKind): JsonNode =
  case kind
  of vkUint:
    result = %reader.readVarUint()
  of vkString:
    result = %reader.readStringValue()
  of vkFloat:
    result = %reader.readFloat32Le()
  of vkColor:
    result = %reader.readUint32Le()
  of vkBytes:
    let bytes = reader.readBytesValue()
    result = newJObject()
    result["byteLength"] = %bytes.len
    let png = pngMetadata(bytes)
    for key, value in png:
      result[key] = value

proc tocKind(code: int): ValueKind =
  case code
  of 0: vkUint
  of 1: vkString
  of 2: vkFloat
  of 3: vkColor
  else: raise newException(ValueError, &"invalid ToC field code {code}")

proc parseWire(options: Options): JsonNode =
  let registry = loadDefs(options.defsPath)
  var reader = WireReader(data: readFile(options.assetPath))

  reader.require(4)
  let fingerprint = reader.data[0 ..< 4]
  reader.offset = 4
  if fingerprint != "RIVE":
    raise reader.fail("invalid Rive fingerprint")

  let major = reader.readVarUint()
  let minor = reader.readVarUint()
  let fileId = reader.readVarUint()

  var tocKeys: seq[uint64]
  while true:
    let key = reader.readVarUint()
    if key == 0: break
    tocKeys.add(key)

  var tocKinds = initTable[uint64, ValueKind]()
  for index, key in tocKeys:
    if index mod 4 == 0:
      let packed = reader.readUint32Le()
      for slot in 0 ..< min(4, tocKeys.len - index):
        tocKinds[tocKeys[index + slot]] = tocKind(int((packed shr (slot * 2)) and 3))

  let streamOffset = reader.offset
  var objects = newJArray()
  var typeCounts = initCountTable[uint64]()
  var propertyCounts = initCountTable[uint64]()

  while reader.offset < reader.data.len:
    let objectOffset = reader.offset
    let typeKey = reader.readVarUint()
    typeCounts.inc(typeKey)
    var objectNode = newJObject()
    objectNode["index"] = %objects.len
    objectNode["byteOffset"] = %objectOffset
    objectNode["typeKey"] = %typeKey
    if registry.types.hasKey(typeKey):
      objectNode["typeName"] = %registry.types[typeKey].name
      objectNode["definition"] = %registry.types[typeKey].source
    else:
      objectNode["typeName"] = %"unknown"
    var properties = newJArray()

    while true:
      let propertyOffset = reader.offset
      let propertyKey = reader.readVarUint()
      if propertyKey == 0: break
      propertyCounts.inc(propertyKey)

      var propertyNode = newJObject()
      propertyNode["byteOffset"] = %propertyOffset
      propertyNode["propertyKey"] = %propertyKey
      var kind: ValueKind
      if registry.properties.hasKey(propertyKey):
        let definition = registry.properties[propertyKey]
        propertyNode["propertyName"] = %definition.name
        propertyNode["declaredType"] = %definition.schemaType
        propertyNode["runtimeType"] = %definition.runtimeType
        propertyNode["isReference"] = %(definition.schemaType == "Id")
        propertyNode["definition"] = %definition.source
        kind = definition.kind
      elif tocKinds.hasKey(propertyKey):
        propertyNode["propertyName"] = %"unknown"
        propertyNode["declaredType"] = %"toc"
        kind = tocKinds[propertyKey]
      else:
        raise reader.fail(&"property key {propertyKey} is absent from defs and ToC")
      propertyNode["wireKind"] = %($kind)
      propertyNode["value"] = reader.propertyValue(kind)
      properties.add(propertyNode)
    objectNode["properties"] = properties
    objects.add(objectNode)

  proc sortedCountJson(counts: CountTable[uint64]): JsonNode =
    result = newJObject()
    var keys: seq[uint64]
    for key in counts.keys: keys.add(key)
    keys.sort()
    for key in keys:
      result[$key] = %counts[key]

  var toc = newJArray()
  for key in tocKeys:
    var item = newJObject()
    item["propertyKey"] = %key
    item["wireKind"] = %($tocKinds[key])
    if registry.properties.hasKey(key):
      item["propertyName"] = %registry.properties[key].name
    else:
      item["propertyName"] = %"unknown"
    toc.add(item)

  result = newJObject()
  result["schemaVersion"] = %1
  result["officialRuntimeSha"] = %options.runtimeSha
  result["asset"] = %*{
    "pathLabel": extractFilename(options.assetPath),
    "byteLength": reader.data.len,
    "major": major,
    "minor": minor,
    "fileId": fileId
  }
  result["streamOffset"] = %streamOffset
  result["toc"] = toc
  result["objectCount"] = %objects.len
  result["typeCounts"] = sortedCountJson(typeCounts)
  result["propertyCounts"] = sortedCountJson(propertyCounts)
  result["objects"] = objects

proc parseOptions(): Options =
  var parser = initOptParser(commandLineParams())
  while true:
    parser.next()
    case parser.kind
    of cmdEnd: break
    of cmdLongOption, cmdShortOption:
      case parser.key
      of "asset": result.assetPath = parser.val
      of "defs": result.defsPath = parser.val
      of "output": result.outputPath = parser.val
      of "runtime-sha": result.runtimeSha = parser.val
      else: raise newException(ValueError, "unknown option: --" & parser.key)
    of cmdArgument:
      raise newException(ValueError, "unexpected argument: " & parser.key)
  if result.assetPath.len == 0 or result.defsPath.len == 0 or
      result.outputPath.len == 0 or result.runtimeSha.len == 0:
    raise newException(ValueError,
      "usage: rive_wire_audit --asset:PATH --defs:PATH --output:PATH " &
      "--runtime-sha:SHA")

when isMainModule:
  let options = parseOptions()
  let audit = parseWire(options)
  writeFile(options.outputPath, audit.pretty(indent = 2) & "\n")
  echo &"wrote {audit[\"objectCount\"].getInt()} objects to {options.outputPath}"
