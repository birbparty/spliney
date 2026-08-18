## Deterministically generate Spliney's wire metadata from a pinned Rive tree.

import std/[algorithm, json, os, sequtils, strformat, strutils, tables]

type
  Options = object
    defsDir: string
    outputPath: string
    runtimeSha: string
    defsSha: string

  TypeEntry = object
    key: uint32
    name: string
    source: string
    parentSource: string
    parentKey: uint32
    mixins: seq[string]

  PropertyEntry = object
    key: uint32
    name: string
    ownerName: string
    ownerSource: string
    ownerTypeKey: uint32
    schemaType: string
    runtimeType: string
    wireKind: string
    backingCode: uint8
    isReference: bool
    initialValue: string
    initialValueRuntime: string

proc usage() =
  stderr.writeLine "usage: generate_rive_registry --defs DIR --output FILE --runtime-sha SHA --defs-sha SHA"

proc parseArguments(): Options =
  let arguments = commandLineParams()
  var index = 0
  while index < arguments.len:
    if arguments[index] == "--":
      inc index
      continue
    if index + 1 >= arguments.len:
      usage()
      quit 2
    case arguments[index]
    of "--defs": result.defsDir = arguments[index + 1]
    of "--output": result.outputPath = arguments[index + 1]
    of "--runtime-sha": result.runtimeSha = arguments[index + 1]
    of "--defs-sha": result.defsSha = arguments[index + 1]
    else:
      usage()
      quit 2
    index += 2
  if result.defsDir.len == 0 or result.outputPath.len == 0 or
      result.runtimeSha.len == 0 or result.defsSha.len == 0:
    usage()
    quit 2

proc runtimeProperty(node: JsonNode): bool =
  not node.hasKey("runtime") or node["runtime"].getBool

proc nodeText(node: JsonNode, key: string): string =
  if not node.hasKey(key): return ""
  case node[key].kind
  of JString: node[key].getStr
  else: $node[key]

proc wireMetadata(runtimeType: string): tuple[kind: string, code: uint8] =
  case runtimeType
  of "Bytes": ("bytes", 1'u8)
  of "String": ("string", 1'u8)
  of "double": ("float", 2'u8)
  of "Color": ("color", 3'u8)
  else: ("uint", 0'u8)

proc nimString(value: string): string = escape(value)

proc loadEntries(defsDir: string): tuple[types: seq[TypeEntry],
    properties: seq[PropertyEntry], fileCount: int] =
  var paths: seq[string]
  for path in walkDirRec(defsDir):
    if path.endsWith(".json"):
      paths.add path
  paths.sort
  result.fileCount = paths.len
  if result.fileCount == 0:
    raise newException(ValueError, "defs directory contains no JSON files")

  var documents = initTable[string, JsonNode]()
  var typeKeysBySource = initTable[string, uint32]()
  var typeKeySources = initTable[uint32, string]()
  var typeNames = initTable[string, string]()
  for path in paths:
    let source = relativePath(path, defsDir)
    let document = parseFile(path)
    documents[source] = document
    if document.hasKey("key") and document["key"].hasKey("int"):
      let key = document["key"]["int"].getInt.uint32
      if key == 0:
        raise newException(ValueError, "type key zero in " & source)
      if typeKeySources.hasKey(key):
        raise newException(ValueError,
          &"duplicate type key {key}: {typeKeySources[key]} and {source}")
      let name = document["name"].getStr
      if typeNames.hasKey(name):
        raise newException(ValueError,
          &"duplicate type name {name}: {typeNames[name]} and {source}")
      typeKeySources[key] = source
      typeKeysBySource[source] = key
      typeNames[name] = source

  var propertyKeySources = initTable[uint32, string]()
  for source in documents.keys.toSeq.sorted:
    let document = documents[source]
    let ownerName = if document.hasKey("name"): document["name"].getStr else: ""
    let ownerKey = typeKeysBySource.getOrDefault(source)
    if ownerKey != 0:
      var entry = TypeEntry(
        key: ownerKey,
        name: ownerName,
        source: source,
        parentSource: document.nodeText("extends"))
      if entry.parentSource.len > 0:
        if not documents.hasKey(entry.parentSource):
          raise newException(ValueError,
            &"missing parent {entry.parentSource} referenced by {source}")
        entry.parentKey = typeKeysBySource.getOrDefault(entry.parentSource)
      if document.hasKey("mixins"):
        for mixinNode in document["mixins"]:
          let mixinSource = mixinNode.getStr
          entry.mixins.add mixinSource
      result.types.add entry

    if not document.hasKey("properties"): continue
    for name, node in document["properties"]:
      if not node.runtimeProperty or not node.hasKey("key") or
          not node["key"].hasKey("int"):
        continue
      let key = node["key"]["int"].getInt.uint32
      if key == 0:
        raise newException(ValueError, "property key zero in " & source)
      if propertyKeySources.hasKey(key):
        raise newException(ValueError,
          &"duplicate property key {key}: {propertyKeySources[key]} and {source}")
      propertyKeySources[key] = source
      let schemaType = node["type"].getStr
      let runtimeType = if node.hasKey("typeRuntime"):
          node["typeRuntime"].getStr else: schemaType
      let wire = wireMetadata(runtimeType)
      result.properties.add PropertyEntry(
        key: key,
        name: name,
        ownerName: ownerName,
        ownerSource: source,
        ownerTypeKey: ownerKey,
        schemaType: schemaType,
        runtimeType: runtimeType,
        wireKind: wire.kind,
        backingCode: wire.code,
        isReference: schemaType == "Id",
        initialValue: node.nodeText("initialValue"),
        initialValueRuntime: node.nodeText("initialValueRuntime"))

  result.types.sort(proc(a, b: TypeEntry): int = cmp(a.key, b.key))
  result.properties.sort(proc(a, b: PropertyEntry): int = cmp(a.key, b.key))

  var visiting = initTable[uint32, bool]()
  var visited = initTable[uint32, bool]()
  var byKey = initTable[uint32, TypeEntry]()
  for entry in result.types: byKey[entry.key] = entry
  proc visit(key: uint32) =
    if visited.getOrDefault(key): return
    if visiting.getOrDefault(key):
      raise newException(ValueError, &"inheritance cycle at type key {key}")
    visiting[key] = true
    let parentKey = byKey[key].parentKey
    if parentKey != 0: visit(parentKey)
    visiting[key] = false
    visited[key] = true
  for entry in result.types: visit(entry.key)

proc generate(options: Options): string =
  let entries = loadEntries(options.defsDir)
  result.add "## Generated by tools/generate_rive_registry.nim. DO NOT EDIT.\n"
  result.add &"## Official runtime: {options.runtimeSha}\n"
  result.add &"## dev/defs aggregate SHA-256: {options.defsSha}\n\n"
  result.add "type\n"
  result.add "  WireKind* {.pure.} = enum\n"
  result.add "    uintValue, stringValue, floatValue, colorValue, bytesValue\n\n"
  result.add "  TypeMetadata* = object\n"
  result.add "    key*: uint32\n    name*: string\n    source*: string\n"
  result.add "    parentKey*: uint32\n    parentSource*: string\n    mixins*: seq[string]\n\n"
  result.add "  PropertyMetadata* = object\n"
  result.add "    key*: uint32\n    name*: string\n    ownerName*: string\n"
  result.add "    ownerSource*: string\n    ownerTypeKey*: uint32\n"
  result.add "    schemaType*: string\n    runtimeType*: string\n"
  result.add "    wireKind*: WireKind\n    backingCode*: uint8\n"
  result.add "    isReference*: bool\n    initialValue*: string\n"
  result.add "    initialValueRuntime*: string\n\n"
  result.add "  GeneratedCoreObject* = ref object of RootObj\n"
  result.add "    typeKey*: uint32\n\n"
  result.add "  CoreFactoryProc* = proc(): GeneratedCoreObject {.nimcall.}\n\n"
  result.add "const\n"
  result.add &"  OfficialRuntimeSha* = {options.runtimeSha.nimString}\n"
  result.add &"  DefsAggregateSha256* = {options.defsSha.nimString}\n"
  result.add &"  DefsFileCount* = {entries.fileCount}\n"
  result.add &"  TypeCount* = {entries.types.len}\n"
  result.add &"  PropertyCount* = {entries.properties.len}\n\n"
  result.add "  TypeRegistry* = [\n"
  for index, entry in entries.types:
    result.add "    TypeMetadata("
    result.add &"key: {entry.key}'u32, name: {entry.name.nimString}, "
    result.add &"source: {entry.source.nimString}, parentKey: {entry.parentKey}'u32, "
    result.add &"parentSource: {entry.parentSource.nimString}, mixins: @["
    result.add entry.mixins.mapIt(it.nimString).join(", ")
    result.add "])"
    result.add(if index == entries.types.high: "\n" else: ",\n")
  result.add "  ]\n\n"
  result.add "  PropertyRegistry* = [\n"
  for index, entry in entries.properties:
    result.add "    PropertyMetadata("
    result.add &"key: {entry.key}'u32, name: {entry.name.nimString}, "
    result.add &"ownerName: {entry.ownerName.nimString}, ownerSource: {entry.ownerSource.nimString}, "
    result.add &"ownerTypeKey: {entry.ownerTypeKey}'u32, schemaType: {entry.schemaType.nimString}, "
    result.add &"runtimeType: {entry.runtimeType.nimString}, wireKind: WireKind.{entry.wireKind}Value, "
    result.add &"backingCode: {entry.backingCode}'u8, isReference: {entry.isReference}, "
    result.add &"initialValue: {entry.initialValue.nimString}, "
    result.add &"initialValueRuntime: {entry.initialValueRuntime.nimString})"
    result.add(if index == entries.properties.high: "\n" else: ",\n")
  result.add "  ]\n\n"
  result.add "proc typeMetadata*(key: uint32): ptr TypeMetadata =\n"
  result.add "  var low = 0\n  var high = TypeRegistry.high\n"
  result.add "  while low <= high:\n    let middle = (low + high) shr 1\n"
  result.add "    if TypeRegistry[middle].key == key: return unsafeAddr TypeRegistry[middle]\n"
  result.add "    if TypeRegistry[middle].key < key: low = middle + 1\n    else: high = middle - 1\n\n"
  result.add "proc propertyMetadata*(key: uint32): ptr PropertyMetadata =\n"
  result.add "  var low = 0\n  var high = PropertyRegistry.high\n"
  result.add "  while low <= high:\n    let middle = (low + high) shr 1\n"
  result.add "    if PropertyRegistry[middle].key == key: return unsafeAddr PropertyRegistry[middle]\n"
  result.add "    if PropertyRegistry[middle].key < key: low = middle + 1\n    else: high = middle - 1\n\n"
  result.add "proc registerFactory*(factories: var seq[tuple[key: uint32, factory: CoreFactoryProc]];\n"
  result.add "    key: uint32; factory: CoreFactoryProc) =\n"
  result.add "  if typeMetadata(key).isNil: raise newException(ValueError, \"unknown generated type key\")\n"
  result.add "  for item in factories:\n    if item.key == key: raise newException(ValueError, \"duplicate core factory\")\n"
  result.add "  factories.add (key, factory)\n\n"
  result.add "proc instantiate*(factories: openArray[tuple[key: uint32, factory: CoreFactoryProc]];\n"
  result.add "    key: uint32): GeneratedCoreObject =\n"
  result.add "  for item in factories:\n    if item.key == key:\n      result = item.factory()\n      result.typeKey = key\n      return\n"

proc main() =
  let options = parseArguments()
  let output = generate(options)
  createDir(parentDir(options.outputPath))
  writeFile(options.outputPath, output)
  echo &"generated {options.outputPath}"

when isMainModule:
  main()
