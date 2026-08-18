## Gate 0 headless embedded-PNG preparation experiment.
##
## Naylib is imported only by this non-shipping adapter probe. The executable
## decodes before any optional window/context initialization and maps decoder
## exceptions to the stable Spliney error contract.

import std/[json, os, strformat]

import raylib
import spliney/contracts

const
  ExpectedAssetSha = "7a2f1d58da22e12932e73e76366b48651e66d9980153ece5433188c8fd08bc35"
  ExpectedRuntimeSha = "372b8092e940f32cf84499ae23a4899ec66a9ab1"

type
  DecodedPng = object
    image: Image

  DecodeResult = object
    case isOk: bool
    of true:
      value: DecodedPng
    of false:
      error: SplineyError

proc usage() =
  stderr.writeLine "usage: raylib_png_decode_probe --oracle FILE --reference-dir DIR --output-dir DIR [--verify-upload]"

proc parseArguments(): tuple[oracle, referenceDir, outputDir: string,
    verifyUpload: bool] =
  let arguments = commandLineParams()
  var index = 0
  while index < arguments.len:
    case arguments[index]
    of "--verify-upload":
      result.verifyUpload = true
      inc index
    of "--oracle", "--reference-dir", "--output-dir":
      if index + 1 >= arguments.len:
        usage()
        quit 2
      case arguments[index]
      of "--oracle": result.oracle = arguments[index + 1]
      of "--reference-dir": result.referenceDir = arguments[index + 1]
      of "--output-dir": result.outputDir = arguments[index + 1]
      else: discard
      index += 2
    else:
      usage()
      quit 2
  if result.oracle.len == 0 or result.referenceDir.len == 0 or
      result.outputDir.len == 0:
    usage()
    quit 2

proc mappedDecode(payload: openArray[byte], assetId: int64): DecodeResult =
  try:
    var image = loadImageFromMemory(".png", payload)
    imageFormat(image, UncompressedR8g8b8a8)
    DecodeResult(isOk: true, value: DecodedPng(image: move(image)))
  except RaylibError:
    DecodeResult(isOk: false, error: SplineyError(
      category: ErrorCategory.assetDecode,
      stage: ErrorStage.imageDecode,
      message: "embedded PNG decode failed",
      context: ErrorContext(
        objectTypeKey: -1,
        propertyKey: -1,
        assetId: assetId,
        animationIndex: -1)))

proc imageBytes(image: Image): seq[byte] =
  let length = image.width.int * image.height.int * 4
  result = newSeq[byte](length)
  if length > 0:
    copyMem(addr result[0], image.data, length)

proc verifyGpuUpload(images: openArray[DecodedPng]): int =
  for decoded in images:
    var texture = loadTextureFromImage(decoded.image)
    if not isTextureValid(texture) or texture.width != decoded.image.width or
        texture.height != decoded.image.height or
        texture.format != UncompressedR8g8b8a8:
      raise newException(ValueError, "post-window texture upload mismatch")
    inc result

proc main() =
  let arguments = parseArguments()
  let oracle = parseFile(arguments.oracle)
  if oracle["assetSha256"].getStr != ExpectedAssetSha or
      oracle["officialRuntimeSha"].getStr != ExpectedRuntimeSha:
    raise newException(ValueError, "oracle dependency pin mismatch")
  createDir(arguments.outputDir)

  var decodedImages: seq[DecodedPng]
  var imageReport = newJArray()
  for metadata in oracle["images"]:
    let index = metadata["index"].getInt
    let encoded = readFile(arguments.referenceDir /
      metadata["encodedFilename"].getStr)
    if encoded.len == 0:
      raise newException(ValueError, &"embedded image {index} is empty")
    var outcome = mappedDecode(encoded.toOpenArrayByte(0, encoded.high), index)
    if not outcome.isOk:
      raise newException(ValueError, &"embedded image {index} did not decode")
    if outcome.value.image.width != metadata["width"].getInt.int32 or
        outcome.value.image.height != metadata["height"].getInt.int32:
      raise newException(ValueError, &"embedded image {index} dimensions differ")
    let raw = imageBytes(outcome.value.image)
    let rawFilename = &"decoded-image-{index:02}.rgba"
    writeFile(arguments.outputDir / rawFilename, raw)
    imageReport.add %*{
      "index": index,
      "encodedSha256": metadata["encodedSha256"].getStr,
      "width": outcome.value.image.width,
      "height": outcome.value.image.height,
      "pixelFormat": "RGBA8",
      "rowOrientation": "top-to-bottom",
      "alpha": "straight",
      "decodedBytes": raw.len,
      "decodedFilename": rawFilename
    }
    decodedImages.add move(outcome.value)

  # A damaged signature must be a returned, sanitized asset-decode error.
  var corrupt = readFile(arguments.referenceDir /
    oracle["images"][0]["encodedFilename"].getStr)
  for index in 0 ..< min(8, corrupt.len):
    corrupt[index] = char(index)
  let corruptOutcome = mappedDecode(
    corrupt.toOpenArrayByte(0, corrupt.high), 0)
  if corruptOutcome.isOk or
      corruptOutcome.error.category != ErrorCategory.assetDecode or
      corruptOutcome.error.stage != ErrorStage.imageDecode or
      corruptOutcome.error.context.assetId != 0 or
      corruptOutcome.error.message != "embedded PNG decode failed":
    raise newException(ValueError, "corrupt PNG error mapping mismatch")

  var uploaded = 0
  if arguments.verifyUpload:
    # All Image owners already exist here. The context is created only for the
    # distinct GPU acquisition stage, and every Texture dies before close.
    initWindow(64, 64, "Spliney Gate 0 PNG upload probe")
    try:
      uploaded = verifyGpuUpload(decodedImages)
    finally:
      closeWindow()

  let report = %*{
    "schemaVersion": 1,
    "assetSha256": ExpectedAssetSha,
    "officialRuntimeSha": ExpectedRuntimeSha,
    "decoder": "Raylib LoadImageFromMemory (.png/stb_image)",
    "naylibVersion": "26.08.0",
    "naylibRevision": "19dd4e7e34c705c677e89b3a6516846c9f2e0125",
    "headlessDecodeCount": decodedImages.len,
    "windowCreatedForDecode": false,
    "verifyUpload": arguments.verifyUpload,
    "gpuUploadCount": uploaded,
    "images": imageReport,
    "corruptInput": {
      "category": "assetDecode",
      "stage": "imageDecode",
      "assetId": corruptOutcome.error.context.assetId,
      "message": corruptOutcome.error.message
    }
  }
  writeFile(arguments.outputDir / "decode-report.json", report.pretty & "\n")
  echo "headless PNG decodes: ", decodedImages.len
  echo "post-window GPU uploads: ", uploaded
  echo "corrupt PNG: assetDecode/imageDecode"

when isMainModule:
  main()
