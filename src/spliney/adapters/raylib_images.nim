## Opt-in Naylib/Raylib implementation of embedded PNG preparation.

when not defined(useNaylib):
  {.error: "spliney/adapters/raylib_images requires -d:useNaylib".}

import raylib

import spliney/errors
import spliney/render/protocol

type
  RaylibPreparedImage* = ref object of RenderImage
    assetIndex*: uint32
    cpuImage*: Image
    texture*: Texture2D
    cpuReady*: bool
    textureReady*: bool
    released*: bool

  RaylibImageFactory* = ref object of Factory
    decodeCount*: int
    uploadCount*: int
    releaseCount*: int

  RaylibFactory* = RaylibImageFactory

proc imageError(category: ErrorCategory; stage: ErrorStage; message: string;
    assetIndex: uint32; name: string): SplineyResult[PreparedImage] =
  err[PreparedImage](SplineyError(
    category: category,
    stage: stage,
    message: message,
    context: ErrorContext(
      objectTypeKey: 105,
      propertyKey: 212,
      assetId: assetIndex.int64,
      assetName: name,
      animationIndex: -1)))

method prepareEmbeddedPng*(factory: RaylibImageFactory; assetIndex: uint32;
    name: string; compressedBytes: openArray[byte]; expectedWidth,
    expectedHeight: uint32): SplineyResult[PreparedImage] =
  if not isWindowReady():
    return imageError(ErrorCategory.backend,
      ErrorStage.contextInitialization,
      "Raylib context is not ready", assetIndex, name)
  var prepared = RaylibPreparedImage(assetIndex: assetIndex)
  try:
    prepared.cpuImage = loadImageFromMemory(".png", compressedBytes)
    prepared.cpuReady = isImageValid(prepared.cpuImage)
    if not prepared.cpuReady:
      return imageError(ErrorCategory.assetDecode, ErrorStage.imageDecode,
        "embedded PNG decode failed", assetIndex, name)
    imageFormat(prepared.cpuImage, UncompressedR8g8b8a8)
    if prepared.cpuImage.width != expectedWidth.int32 or
        prepared.cpuImage.height != expectedHeight.int32 or
        prepared.cpuImage.format != UncompressedR8g8b8a8:
      prepared.cpuImage = default(Image)
      prepared.cpuReady = false
      return imageError(ErrorCategory.assetDecode, ErrorStage.imageDecode,
        "embedded PNG dimensions or format differ", assetIndex, name)
    inc factory.decodeCount
  except RaylibError:
    if prepared.cpuReady:
      prepared.cpuImage = default(Image)
      prepared.cpuReady = false
    return imageError(ErrorCategory.assetDecode, ErrorStage.imageDecode,
      "embedded PNG decode failed", assetIndex, name)

  try:
    prepared.texture = loadTextureFromImage(prepared.cpuImage)
    prepared.textureReady = isTextureValid(prepared.texture)
    if not prepared.textureReady:
      prepared.cpuImage = default(Image)
      prepared.cpuReady = false
      return imageError(ErrorCategory.backend, ErrorStage.resourceAcquisition,
        "embedded PNG texture upload failed", assetIndex, name)
    setTextureFilter(prepared.texture, Bilinear)
    setTextureWrap(prepared.texture, Clamp)
    inc factory.uploadCount
    prepared.configureImage(expectedWidth.int, expectedHeight.int)
    ok[PreparedImage](prepared)
  except RaylibError:
    if prepared.textureReady:
      prepared.texture = default(Texture2D)
      prepared.textureReady = false
    if prepared.cpuReady:
      prepared.cpuImage = default(Image)
      prepared.cpuReady = false
    imageError(ErrorCategory.backend, ErrorStage.resourceAcquisition,
      "embedded PNG texture upload failed", assetIndex, name)

method releasePreparedImage*(factory: RaylibImageFactory;
    image: PreparedImage): SplineyStatus =
  if not (image of RaylibPreparedImage): return okStatus()
  let prepared = RaylibPreparedImage(image)
  if prepared.released: return okStatus()
  prepared.released = true
  if prepared.textureReady:
    prepared.texture = default(Texture2D)
    prepared.textureReady = false
  if prepared.cpuReady:
    prepared.cpuImage = default(Image)
    prepared.cpuReady = false
  inc factory.releaseCount
  okStatus()
