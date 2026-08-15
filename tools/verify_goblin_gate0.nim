## Verifies that the private Gate 0 evidence is complete enough to freeze the
## exact-asset implementation floor. This program reads metadata only.

import std/[json, os, parseopt, strformat, tables]

type Options = object
  wirePath: string
  oraclePath: string
  baselinePath: string

const
  ExpectedAssetSha = "7a2f1d58da22e12932e73e76366b48651e66d9980153ece5433188c8fd08bc35"
  ExpectedRuntimeSha = "372b8092e940f32cf84499ae23a4899ec66a9ab1"
  ExpectedTimeline1StartSha = "ac3e882aee9eb8a9ec1f8786a6084160fe1002ee935a9289211130048d6d8cef"
  ExpectedTimeline1DirectSha = "f617ff1b0a89c16b09f3afb8c0e001d5158da7775b82c27d8faf66bc88e7f126"

proc expect(condition: bool; message: string) =
  if not condition:
    raise newException(ValueError, message)

proc countKinds(items: JsonNode): CountTable[string] =
  for item in items:
    result.inc(item["kind"].getStr())

proc parseOptions(): Options =
  var parser = initOptParser(commandLineParams())
  while true:
    parser.next()
    case parser.kind
    of cmdEnd: break
    of cmdLongOption, cmdShortOption:
      case parser.key
      of "": discard # Nim c -r passes the conventional `--` separator through.
      of "wire": result.wirePath = parser.val
      of "oracle": result.oraclePath = parser.val
      of "baseline": result.baselinePath = parser.val
      else: raise newException(ValueError, "unknown option: --" & parser.key)
    of cmdArgument:
      raise newException(ValueError, "unexpected argument: " & parser.key)
  expect(result.wirePath.len > 0 and result.oraclePath.len > 0 and
    result.baselinePath.len > 0,
    "usage: verify_goblin_gate0 --wire:PATH --oracle:PATH --baseline:PATH")

proc verifyWire(wire: JsonNode) =
  expect(wire["schemaVersion"].getInt() == 1, "unexpected wire schema")
  expect(wire["officialRuntimeSha"].getStr() == ExpectedRuntimeSha,
    "wire runtime pin mismatch")
  let asset = wire["asset"]
  expect(asset["byteLength"].getInt() == 115468, "asset byte length mismatch")
  expect(asset["major"].getInt() == 7 and asset["minor"].getInt() == 3,
    "Rive version mismatch")
  expect(wire["objectCount"].getInt() == 525, "object count mismatch")
  expect(wire["toc"].len == 35, "ToC property count mismatch")
  expect(wire["propertyCounts"].len == 81, "serialized property count mismatch")

  for objectNode in wire["objects"]:
    expect(objectNode["typeName"].getStr() != "unknown",
      &"unknown type key {objectNode[\"typeKey\"].getInt()}")
    for propertyNode in objectNode["properties"]:
      expect(propertyNode["propertyName"].getStr() != "unknown",
        &"unknown property key {propertyNode[\"propertyKey\"].getInt()}")
      if propertyNode.hasKey("isReference") and propertyNode["isReference"].getBool():
        expect(propertyNode["declaredType"].getStr() == "Id",
          "reference classification lost schema type")

  let requiredTypes = {
    "1": 1, "2": 4, "18": 1, "20": 1, "23": 1,
    "25": 20, "26": 51, "30": 173, "31": 3,
    "40": 4, "41": 2, "43": 2, "44": 6, "45": 81,
    "53": 1, "57": 1, "61": 5, "62": 1, "63": 1,
    "64": 1, "65": 3, "81": 2, "83": 1, "100": 13,
    "105": 13, "106": 13, "109": 3, "111": 107,
    "169": 1, "420": 1, "431": 1, "435": 2, "437": 2,
    "442": 1, "447": 1, "515": 1}.toTable
  expect(wire["typeCounts"].len == requiredTypes.len,
    "serialized type-key set changed")
  for key, count in requiredTypes:
    expect(wire["typeCounts"].hasKey(key) and
      wire["typeCounts"][key].getInt() == count,
      &"type {key} count mismatch")

proc verifyBaseline(baseline: JsonNode) =
  expect(baseline["asset"]["sha256"].getStr() == ExpectedAssetSha,
    "baseline asset hash mismatch")
  expect(baseline["officialRuntime"]["gitSha"].getStr() == ExpectedRuntimeSha,
    "baseline runtime hash mismatch")
  let artboard = baseline["artboards"][0]
  expect(artboard["name"].getStr() == "Artboard", "default artboard mismatch")
  expect(artboard["bounds"]["width"].getInt() == 500 and
    artboard["bounds"]["height"].getInt() == 500, "artboard bounds mismatch")
  let animations = baseline["defaultArtboard"]["linearAnimations"]
  expect(animations.len == 3, "animation count mismatch")
  expect(animations[0]["name"].getStr() == "Timeline 1" and
    animations[1]["name"].getStr() == "Timeline 2" and
    animations[2]["name"].getStr() == "Timeline 3",
    "animation order mismatch")
  expect(baseline["assetSummary"]["embeddedImagesDecoded"].getInt() == 13,
    "baseline did not decode all embedded images")

proc verifyOracle(oracle: JsonNode) =
  expect(oracle["schemaVersion"].getInt() == 1, "unexpected oracle schema")
  expect(oracle["assetSha256"].getStr() == ExpectedAssetSha,
    "oracle asset hash mismatch")
  expect(oracle["officialRuntimeSha"].getStr() == ExpectedRuntimeSha,
    "oracle runtime hash mismatch")
  expect(oracle["tolerance"]["absolute"].getFloat() <= 0.0001 and
    oracle["tolerance"]["relative"].getFloat() <= 0.00001,
    "oracle tolerances are too broad")
  expect(oracle["images"].len == 13, "decoded image count mismatch")
  for image in oracle["images"]:
    expect(image["encodedBytes"].getInt() > 0 and
      image["encodedSha256"].getStr().len == 64 and
      image["width"].getInt() > 0 and image["height"].getInt() > 0,
      "invalid decoded image evidence")

  let animations = oracle["animations"]
  expect(animations.len == 3, "oracle animation count mismatch")
  let expectedNames = ["Timeline 1", "Timeline 2", "Timeline 3"]
  let expectedAnimated = [39, 5, 7]
  for animationIndex in 0 ..< animations.len:
    let animation = animations[animationIndex]
    expect(animation["name"].getStr() == expectedNames[animationIndex],
      "oracle animation order mismatch")
    expect(animation["states"].len == 3, "missing fixed oracle states")
    for state in animation["states"]:
      expect(state["transforms"].len == 6, "bone/root transform coverage mismatch")
      expect(state["constraints"].len == 3, "constraint coverage mismatch")
      expect(state["animatedProperties"].len == expectedAnimated[animationIndex],
        "animated property coverage mismatch")
      let solverKinds = countKinds(state["solverObjects"])
      expect(solverKinds["skin"] == 2 and solverKinds["tendon"] == 6 and
        solverKinds["weight"] == 81 and solverKinds["mesh"] == 3 and
        solverKinds["contourMeshVertex"] == 107,
        "solver object coverage mismatch")
      expect(state["visibleFill"].len == 2, "solid/fill evidence missing")
      expect(state["drawStackBalanced"].getBool(), "draw stack is unbalanced")
      var meshCount = 0
      var vertexCount = 0
      var indexCount = 0
      var pathCount = 0
      for command in state["drawCommands"]:
        case command["kind"].getStr()
        of "imageMesh":
          inc meshCount
          vertexCount += command["vertices"].len
          indexCount += command["indices"].len
          expect(command["imageIndex"].getInt() >= 0,
            "mesh command lost image identity")
        of "path": inc pathCount
        of "clip": expect(false, "unexpected visible clip command")
        else: discard
      expect(meshCount == 3 and vertexCount == 107 and indexCount == 300,
        "complete textured mesh draw coverage mismatch")
      expect(pathCount == 1, "visible solid fill draw missing")
    expect(animation["referenceFrames"].len == 3,
      "reference frame set is incomplete")
    for frame in animation["referenceFrames"]:
      expect(frame["sha256"].getStr().len == 64 and
        frame["foregroundPixels"].getInt() >= 256,
        "invalid reference frame evidence")
  expect(animations[0]["referenceFrames"][0]["sha256"].getStr() ==
    ExpectedTimeline1StartSha, "Timeline 1 start hash mismatch")
  expect(animations[0]["referenceFrames"][2]["sha256"].getStr() ==
    ExpectedTimeline1DirectSha, "Timeline 1 authoritative 2-second hash mismatch")
  expect(animations[0]["changedPixels"]["direct"].getInt() == 22558,
    "Timeline 1 authoritative changed-pixel count mismatch")
  expect(animations[0]["changedPixels"]["boundedVsDirect"].getInt() == 8,
    "Timeline 1 step-sequence distinction changed")
  expect(animations[1]["changedPixels"]["boundedVsDirect"].getInt() == 0 and
    animations[2]["changedPixels"]["boundedVsDirect"].getInt() == 0,
    "short animation step sequence unexpectedly diverged")

when isMainModule:
  let options = parseOptions()
  let wire = parseFile(options.wirePath)
  let oracle = parseFile(options.oraclePath)
  let baseline = parseFile(options.baselinePath)
  verifyWire(wire)
  verifyBaseline(baseline)
  verifyOracle(oracle)
  echo "Gate 0 asset audit verified: 525 wire objects, 13 images, 3 animations, " &
    "6 bone/root transforms, 3 constraints, and 107 deformed vertices per state"
