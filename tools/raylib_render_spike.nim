## Gate 0 macOS-only decision spike for direct rlgl textured triangles.
##
## This is deliberately a non-shipping tool. It consumes the private snapshot
## emitted by rive_oracle_probe and never searches for that evidence implicitly.

import std/[json, math, os, sequtils, strformat]

import raylib
import rlgl

const
  CanvasWidth = 960'i32
  CanvasHeight = 540'i32
  ExpectedAssetSha = "7a2f1d58da22e12932e73e76366b48651e66d9980153ece5433188c8fd08bc35"
  ExpectedRuntimeSha = "372b8092e940f32cf84499ae23a4899ec66a9ab1"
  Background = Color(r: 245, g: 247, b: 250, a: 255)
  KnownTolerance = 2

type
  MeshPoint = object
    x, y: float32

  Mat2D = array[6, float32]

  Metrics = object
    foregroundPixels: int
    referenceForegroundPixels: int
    intersectionPixels: int
    unionPixels: int
    meanAbsoluteRgbError: float64
    maxChannelError: int
    pixelsOver32: int

proc usage() =
  stderr.writeLine "usage: raylib_render_spike --oracle FILE --reference-dir DIR --output-dir DIR"

proc parseArguments(): tuple[oracle, referenceDir, outputDir: string] =
  let arguments = commandLineParams()
  var index = 0
  while index < arguments.len:
    if index + 1 >= arguments.len:
      usage()
      quit 2
    case arguments[index]
    of "--oracle": result.oracle = arguments[index + 1]
    of "--reference-dir": result.referenceDir = arguments[index + 1]
    of "--output-dir": result.outputDir = arguments[index + 1]
    else:
      usage()
      quit 2
    index += 2
  if result.oracle.len == 0 or result.referenceDir.len == 0 or
      result.outputDir.len == 0:
    usage()
    quit 2

proc meshPoint(node: JsonNode): MeshPoint =
  MeshPoint(x: node[0].getFloat.float32, y: node[1].getFloat.float32)

proc matrix(node: JsonNode): Mat2D =
  for index in 0 ..< result.len:
    result[index] = node[index].getFloat.float32

proc transformed(value: MeshPoint, transform: Mat2D): MeshPoint =
  MeshPoint(
    x: transform[0] * value.x + transform[2] * value.y + transform[4],
    y: transform[1] * value.x + transform[3] * value.y + transform[5]
  )

proc submitTriangles(texture: Texture2D, vertices, uvs: openArray[MeshPoint],
                     indices: openArray[int], transform: Mat2D,
                     opacity: uint8) =
  assert vertices.len == uvs.len
  setTexture(texture.id)
  rlBegin(Triangles)
  for vertexIndex in indices:
    let position = transformed(vertices[vertexIndex], transform)
    texCoord2f(uvs[vertexIndex].x, uvs[vertexIndex].y)
    color4ub(255, 255, 255, opacity)
    vertex2f(position.x, position.y)
  rlEnd()
  setTexture(0)

proc sourceOver(source, background: Color, opacity = 255): Color =
  let alpha = source.a.int * opacity div 255
  proc channel(src, dst: uint8): uint8 =
    ((src.int * alpha + dst.int * (255 - alpha) + 127) div 255).uint8
  Color(
    r: channel(source.r, background.r),
    g: channel(source.g, background.g),
    b: channel(source.b, background.b),
    a: 255
  )

proc channelError(actual, expected: Color): int =
  max(max(abs(actual.r.int - expected.r.int), abs(actual.g.int - expected.g.int)),
      max(abs(actual.b.int - expected.b.int), abs(actual.a.int - expected.a.int)))

proc verifyKnownPixels(capture: Image) =
  const samples = [
    (x: 48'i32, y: 48'i32, source: Color(r: 255, g: 0, b: 0, a: 255), opacity: 255),
    (x: 112'i32, y: 48'i32, source: Color(r: 0, g: 255, b: 0, a: 128), opacity: 255),
    (x: 48'i32, y: 112'i32, source: Color(r: 0, g: 0, b: 255, a: 64), opacity: 255),
    (x: 112'i32, y: 112'i32, source: Color(r: 255, g: 255, b: 0, a: 255), opacity: 255),
    (x: 192'i32, y: 48'i32, source: Color(r: 255, g: 0, b: 0, a: 255), opacity: 128),
    (x: 256'i32, y: 48'i32, source: Color(r: 0, g: 255, b: 0, a: 128), opacity: 128),
    (x: 192'i32, y: 112'i32, source: Color(r: 0, g: 0, b: 255, a: 64), opacity: 128),
    (x: 256'i32, y: 112'i32, source: Color(r: 255, g: 255, b: 0, a: 255), opacity: 128)
  ]
  for sample in samples:
    let actual = getImageColor(capture, sample.x, sample.y)
    let expected = sourceOver(sample.source, Background, sample.opacity)
    let error = channelError(actual, expected)
    if error > KnownTolerance:
      raise newException(ValueError,
        &"known pixel ({sample.x},{sample.y}) expected {expected}, got {actual}, error {error}")

proc isForeground(color: Color): bool =
  color.r != Background.r or color.g != Background.g or
    color.b != Background.b or color.a != Background.a

proc compareRepresentative(actual, reference: Image): Metrics =
  if actual.width != reference.width or actual.height != reference.height:
    raise newException(ValueError, "representative dimensions differ")
  var totalError: int64
  for y in 0 ..< actual.height:
    for x in 0 ..< actual.width:
      # The known-pixel fixture occupies the left edge and is absent from the
      # official representative reference.
      if x < 320:
        continue
      let observed = getImageColor(actual, x, y)
      let expected = getImageColor(reference, x, y)
      let observedForeground = observed.isForeground
      let expectedForeground = expected.isForeground
      if observedForeground:
        inc result.foregroundPixels
      if expectedForeground:
        inc result.referenceForegroundPixels
      if observedForeground and expectedForeground:
        inc result.intersectionPixels
      if observedForeground or expectedForeground:
        inc result.unionPixels
        let red = abs(observed.r.int - expected.r.int)
        let green = abs(observed.g.int - expected.g.int)
        let blue = abs(observed.b.int - expected.b.int)
        totalError += red + green + blue
        result.maxChannelError = max(result.maxChannelError,
                                     max(red, max(green, blue)))
        if max(red, max(green, blue)) > 32:
          inc result.pixelsOver32
  if result.unionPixels > 0:
    result.meanAbsoluteRgbError = totalError.float64 /
      (result.unionPixels * 3).float64

proc runExperiment(oracle: JsonNode, referenceDir, outputDir: string): Metrics =
  let snapshot = oracle["representativeSnapshot"]
  let animationIndex = snapshot["animationIndex"].getInt
  let stateSeconds = snapshot["stateSeconds"].getFloat
  let commandIndex = snapshot["drawCommandIndex"].getInt
  var selectedState: JsonNode
  for state in oracle["animations"][animationIndex]["states"]:
    if abs(state["seconds"].getFloat - stateSeconds) < 1e-9 and
        state["stepMode"].getStr == "bounded-positive":
      selectedState = state
      break
  if selectedState.isNil:
    raise newException(ValueError, "representative state not found")
  let command = selectedState["drawCommands"][commandIndex]
  if command["kind"].getStr != "imageMesh" or command["sampler"].getInt != 0 or
      command["blendMode"].getInt != 3:
    raise newException(ValueError, "representative command is not bilinear-clamp srcOver imageMesh")

  let imageIndex = command["imageIndex"].getInt
  let imageMetadata = oracle["images"][imageIndex]
  let sourcePath = referenceDir / imageMetadata["encodedFilename"].getStr
  let referencePath = referenceDir / snapshot["filename"].getStr
  let encoded = readFile(sourcePath)
  if encoded.len == 0:
    raise newException(ValueError, "representative embedded image is empty")
  var sourceImage = loadImageFromMemory(
    ".png", encoded.toOpenArrayByte(0, encoded.high))
  if sourceImage.width != imageMetadata["width"].getInt.int32 or
      sourceImage.height != imageMetadata["height"].getInt.int32:
    raise newException(ValueError, "representative embedded image dimensions differ")
  var sourceTexture = loadTextureFromImage(sourceImage)
  setTextureFilter(sourceTexture, Bilinear)
  setTextureWrap(sourceTexture, Clamp)

  const knownPixels = [
    Color(r: 255, g: 0, b: 0, a: 255),
    Color(r: 0, g: 255, b: 0, a: 128),
    Color(r: 0, g: 0, b: 255, a: 64),
    Color(r: 255, g: 255, b: 0, a: 255)
  ]
  var knownTexture = loadTextureFromData(knownPixels, 2, 2)
  setTextureFilter(knownTexture, Point)
  setTextureWrap(knownTexture, Clamp)
  var target = loadRenderTexture(CanvasWidth, CanvasHeight)

  let vertices = command["vertices"].getElems.mapIt(meshPoint(it))
  let uvs = command["uvs"].getElems.mapIt(meshPoint(it))
  let indices = command["indices"].getElems.mapIt(it.getInt)
  let transform = matrix(command["transform"])
  let quadVertices = [MeshPoint(x: 16, y: 16), MeshPoint(x: 144, y: 16),
                      MeshPoint(x: 144, y: 144), MeshPoint(x: 16, y: 144)]
  let halfQuadVertices = [MeshPoint(x: 160, y: 16), MeshPoint(x: 288, y: 16),
                          MeshPoint(x: 288, y: 144), MeshPoint(x: 160, y: 144)]
  let quadUvs = [MeshPoint(x: 0, y: 0), MeshPoint(x: 1, y: 0),
                 MeshPoint(x: 1, y: 1), MeshPoint(x: 0, y: 1)]
  let quadIndices = [0, 1, 2, 0, 2, 3]
  textureMode(target):
    clearBackground(Background)
    # Raylib's stock Alpha mode uses SrcAlpha for the alpha channel too. Rive's
    # srcOver contract requires One for source alpha so an opaque destination
    # remains opaque.
    setBlendFactorsSeparate(SrcAlpha, OneMinusSrcAlpha, One,
                            OneMinusSrcAlpha, FuncAdd, FuncAdd)
    setBlendMode(CustomSeparate)
    disableBackfaceCulling()
    submitTriangles(sourceTexture, vertices, uvs, indices, transform,
                    round(command["opacity"].getFloat * 255).uint8)
    submitTriangles(knownTexture, quadVertices, quadUvs, quadIndices,
                    [1'f32, 0, 0, 1, 0, 0], 255)
    submitTriangles(knownTexture, halfQuadVertices, quadUvs, quadIndices,
                    [1'f32, 0, 0, 1, 0, 0], 128)
    drawRenderBatchActive()
    enableBackfaceCulling()
    setBlendMode(Alpha)

  var capture = loadImageFromTexture(target.texture)
  imageFlipVertical(capture)
  if not exportImage(capture, outputDir / "raylib-render-spike.png"):
    raise newException(IOError, "failed to export Raylib capture")
  verifyKnownPixels(capture)
  var reference = loadImage(referencePath)
  result = compareRepresentative(capture, reference)

proc main() =
  let arguments = parseArguments()
  createDir(arguments.outputDir)
  let oracle = parseFile(arguments.oracle)
  if oracle["assetSha256"].getStr != ExpectedAssetSha or
      oracle["officialRuntimeSha"].getStr != ExpectedRuntimeSha:
    raise newException(ValueError, "oracle dependency pin mismatch")
  initWindow(CanvasWidth, CanvasHeight, "Spliney Gate 0 render spike")
  var metrics: Metrics
  try:
    metrics = runExperiment(oracle, arguments.referenceDir, arguments.outputDir)
  finally:
    closeWindow()

  let intersectionOverUnion = if metrics.unionPixels == 0: 0.0
    else: metrics.intersectionPixels.float64 / metrics.unionPixels.float64
  let report = %*{
    "schemaVersion": 1,
    "assetSha256": ExpectedAssetSha,
    "officialRuntimeSha": ExpectedRuntimeSha,
    "naylibVersion": "26.08.0",
    "naylibRevision": "19dd4e7e34c705c677e89b3a6516846c9f2e0125",
    "raylibBindingVersion": "5.5.0",
    "raylibBundledSourceVersion": "5.6-dev",
    "route": "direct-rlgl-textured-triangles",
    "knownPixelTolerance": KnownTolerance,
    "representative": {
      "foregroundPixels": metrics.foregroundPixels,
      "referenceForegroundPixels": metrics.referenceForegroundPixels,
      "intersectionPixels": metrics.intersectionPixels,
      "unionPixels": metrics.unionPixels,
      "intersectionOverUnion": intersectionOverUnion,
      "meanAbsoluteRgbError": metrics.meanAbsoluteRgbError,
      "maxChannelError": metrics.maxChannelError,
      "pixelsOver32": metrics.pixelsOver32
    }
  }
  writeFile(arguments.outputDir / "metrics.json", report.pretty & "\n")
  if metrics.foregroundPixels < 9000 or metrics.referenceForegroundPixels < 9000 or
      intersectionOverUnion < 0.95 or metrics.meanAbsoluteRgbError > 8.0 or
      metrics.pixelsOver32 > 1000:
    raise newException(ValueError, "representative snapshot thresholds failed")
  echo "known pixels: max channel error <= ", KnownTolerance
  echo &"representative: foreground={metrics.foregroundPixels}, reference={metrics.referenceForegroundPixels}, IoU={intersectionOverUnion:.6f}, meanAbsRgb={metrics.meanAbsoluteRgbError:.6f}, pixelsOver32={metrics.pixelsOver32}"

when isMainModule:
  main()
