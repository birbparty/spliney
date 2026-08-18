## Private-fixture macOS capture gate for the production Raylib adapter.

when not defined(useNaylib):
  {.error: "verify_exact_raylib_capture requires -d:useNaylib".}

import std/[json, os, parseopt, strformat]

import raylib

import spliney
import spliney/backends/raylib/renderer

const
  CanvasWidth = 960'i32
  CanvasHeight = 540'i32
  TranslationCanvasWidth = 1160'i32
  ExpectedAssetSha = "7a2f1d58da22e12932e73e76366b48651e66d9980153ece5433188c8fd08bc35"
  ExpectedRuntimeSha = "372b8092e940f32cf84499ae23a4899ec66a9ab1"
  Background = Color(r: 245, g: 247, b: 250, a: 255)

type
  Options = object
    assetPath: string
    oraclePath: string
    referenceDir: string
    outputDir: string

  FrameMetrics = object
    actualForeground: int
    referenceForeground: int
    meanAbsoluteRgba: float64
    pixelsOver16: int
    outsideRoiErrors: int
    changedPixels: int
    referenceChangedPixels: int

proc expect(condition: bool; message: string) =
  if not condition: raise newException(ValueError, message)

proc options(): Options =
  var parser = initOptParser(commandLineParams())
  while true:
    parser.next()
    case parser.kind
    of cmdEnd: break
    of cmdLongOption, cmdShortOption:
      case parser.key
      of "": discard
      of "asset": result.assetPath = parser.val
      of "oracle": result.oraclePath = parser.val
      of "reference-dir": result.referenceDir = parser.val
      of "output-dir": result.outputDir = parser.val
      else: raise newException(ValueError, "unknown option: --" & parser.key)
    of cmdArgument:
      raise newException(ValueError, "unexpected argument: " & parser.key)
  expect(result.assetPath.len > 0 and result.oraclePath.len > 0 and
    result.referenceDir.len > 0 and result.outputDir.len > 0,
    "usage: verify_exact_raylib_capture --asset:PATH --oracle:PATH " &
      "--reference-dir:DIR --output-dir:DIR")

proc channelError(left, right: Color): int =
  max(max(abs(left.r.int - right.r.int), abs(left.g.int - right.g.int)),
    max(abs(left.b.int - right.b.int), abs(left.a.int - right.a.int)))

proc isForeground(color: Color): bool = color.channelError(Background) > 1

proc compareFrame(actual, reference: Image): FrameMetrics =
  expect(actual.width == CanvasWidth and actual.height == CanvasHeight,
    "actual capture dimensions differ")
  expect(reference.width == CanvasWidth and reference.height == CanvasHeight,
    "reference capture dimensions differ")
  var totalError: int64
  const roiLeft = 210'i32
  const roiRightExclusive = 750'i32
  for y in 0 ..< CanvasHeight:
    for x in 0 ..< CanvasWidth:
      let observed = getImageColor(actual, x, y)
      let wanted = getImageColor(reference, x, y)
      if x < roiLeft or x >= roiRightExclusive:
        if observed.channelError(Background) > 1:
          inc result.outsideRoiErrors
        continue
      if observed.isForeground: inc result.actualForeground
      if wanted.isForeground: inc result.referenceForeground
      let red = abs(observed.r.int - wanted.r.int)
      let green = abs(observed.g.int - wanted.g.int)
      let blue = abs(observed.b.int - wanted.b.int)
      let alpha = abs(observed.a.int - wanted.a.int)
      totalError += red + green + blue + alpha
      if max(max(red, green), max(blue, alpha)) > 16:
        inc result.pixelsOver16
  result.meanAbsoluteRgba = totalError.float64 /
    ((roiRightExclusive - roiLeft) * CanvasHeight * 4).float64

proc capture(scene: PlayableScene; resources: PreparedResources;
    renderer: RaylibRenderer; target: RenderTexture2D; width: int32;
    translation = spliney.Vec2()): Image =
  renderer.reset()
  textureMode(target):
    clearBackground(Background)
    let drawn = scene.draw(resources, renderer,
      Rect(minX: 0, minY: 0, maxX: CanvasWidth.float32,
        maxY: CanvasHeight.float32),
      translation)
    if not drawn.isOk:
      raise newException(ValueError, drawn.error.message)
  result = loadImageFromTexture(target.texture)
  imageFlipVertical(result)
  expect(result.width == width and result.height == CanvasHeight,
    "capture target dimensions differ")

proc changedPixels(left, right: Image): int =
  expect(left.width == right.width and left.height == right.height,
    "changed-frame dimensions differ")
  for y in 0 ..< left.height:
    for x in 0 ..< left.width:
      if getImageColor(left, x, y) != getImageColor(right, x, y): inc result

proc verifyTranslation(base, shifted: Image) =
  expect(base.width == TranslationCanvasWidth and
    shifted.width == TranslationCanvasWidth and
    base.height == CanvasHeight and shifted.height == CanvasHeight,
    "translation capture dimensions differ")
  for y in 0 ..< CanvasHeight:
    for x in 0 ..< TranslationCanvasWidth:
      let expectedForeground = x >= 100 and
        getImageColor(base, x - 100, y).isForeground
      let actualColor = getImageColor(shifted, x, y)
      let actualForeground = actualColor.isForeground
      expect(actualForeground == expectedForeground,
        &"translated foreground mismatch at ({x}, {y})")
      if not expectedForeground:
        expect(actualColor == Background,
          &"translated background mismatch at ({x}, {y})")

proc main() =
  let arguments = options()
  let oracle = parseFile(arguments.oraclePath)
  expect(oracle["assetSha256"].getStr == ExpectedAssetSha,
    "asset pin mismatch")
  expect(oracle["officialRuntimeSha"].getStr == ExpectedRuntimeSha,
    "official runtime pin mismatch")
  createDir(arguments.outputDir)

  let imported = loadRiveFile(arguments.assetPath, "g0bl1ntest.riv")
  expect(imported.isOk, if imported.isOk: "" else: imported.error.message)

  initWindow(CanvasWidth, CanvasHeight, "Spliney exact Raylib capture")
  var factory: RaylibImageFactory
  var resources: SplineyResult[PreparedResources]
  var target: RenderTexture2D
  var translationTarget: RenderTexture2D
  var reportAnimations = newJArray()
  var shutdownError = ""
  try:
    factory = newRaylibFactory()
    resources = imported.value.prepareResources(factory)
    expect(resources.isOk,
      if resources.isOk: "" else: resources.error.message)
    expect(factory.decodeCount == 13 and factory.uploadCount == 13,
      "Raylib did not prepare all 13 embedded images")
    target = loadRenderTexture(CanvasWidth, CanvasHeight)
    translationTarget = loadRenderTexture(TranslationCanvasWidth, CanvasHeight)
    let renderer = newRaylibRenderer()

    for animationIndex in 0 ..< oracle["animations"].len:
      let animation = oracle["animations"][animationIndex]
      let sceneResult = imported.value.newScene(0, animationIndex)
      expect(sceneResult.isOk,
        if sceneResult.isOk: "" else: sceneResult.error.message)
      let scene = sceneResult.value
      expect(scene.initialSettle().isOk, "initial settle failed")

      var startCapture = scene.capture(resources.value, renderer, target,
        CanvasWidth)
      let startMetadata = animation["referenceFrames"][0]
      var startReference = loadImage(arguments.referenceDir /
        startMetadata["filename"].getStr)
      let startMetrics = compareFrame(startCapture, startReference)
      expect(exportImage(startCapture, arguments.outputDir /
        startMetadata["filename"].getStr), "failed to export start capture")

      var remaining = animation["targetSeconds"].getFloat.float32
      while remaining > 0:
        let delta = min(0.1'f32, remaining)
        let advanced = scene.advanceAndApply(delta)
        expect(advanced.isOk,
          if advanced.isOk: "" else: advanced.error.message)
        remaining -= delta
        if remaining < 0.0000001'f32: remaining = 0
      var targetCapture = scene.capture(resources.value, renderer, target,
        CanvasWidth)
      let targetOutputMetadata = animation["referenceFrames"][1]
      let targetMetadata = animation["referenceFrames"][2]
      var targetReference = loadImage(arguments.referenceDir /
        targetMetadata["filename"].getStr)
      var targetMetrics = compareFrame(targetCapture, targetReference)
      targetMetrics.changedPixels = changedPixels(startCapture, targetCapture)
      targetMetrics.referenceChangedPixels =
        animation["changedPixels"]["direct"].getInt
      expect(exportImage(targetCapture, arguments.outputDir /
        targetOutputMetadata["filename"].getStr),
        "failed to export target capture")

      for (label, metrics) in [("start", startMetrics),
          ("target", targetMetrics)]:
        expect(metrics.outsideRoiErrors == 0,
          &"{animation[\"name\"].getStr} {label} escaped the ROI")
        expect(metrics.actualForeground >= 256,
          &"{animation[\"name\"].getStr} {label} is empty")
        expect(metrics.referenceForeground >= 1458,
          &"{animation[\"name\"].getStr} {label} reference is too sparse")
        let areaRatio = metrics.actualForeground.float64 /
          metrics.referenceForeground.float64
        expect(areaRatio >= 0.75 and areaRatio <= 1.25,
          &"{animation[\"name\"].getStr} {label} foreground ratio failed")
        expect(metrics.meanAbsoluteRgba <= 2,
          &"{animation[\"name\"].getStr} {label} mean RGBA error failed: " &
            $metrics.meanAbsoluteRgba)
        expect(metrics.pixelsOver16 <= 2916,
          &"{animation[\"name\"].getStr} {label} high-error pixels failed")
      expect(targetMetrics.changedPixels >= 32,
        &"{animation[\"name\"].getStr} did not visibly change")
      expect(targetMetrics.changedPixels.float64 /
        targetMetrics.referenceChangedPixels.float64 >= 0.5,
        &"{animation[\"name\"].getStr} changed-pixel ratio failed")

      reportAnimations.add %*{
        "name": animation["name"].getStr,
        "start": {
          "foregroundPixels": startMetrics.actualForeground,
          "referenceForegroundPixels": startMetrics.referenceForeground,
          "meanAbsoluteRgba": startMetrics.meanAbsoluteRgba,
          "pixelsOver16": startMetrics.pixelsOver16,
          "outsideRoiErrors": startMetrics.outsideRoiErrors
        },
        "target": {
          "referenceFilename": targetMetadata["filename"].getStr,
          "referenceSha256": targetMetadata["sha256"].getStr,
          "foregroundPixels": targetMetrics.actualForeground,
          "referenceForegroundPixels": targetMetrics.referenceForeground,
          "meanAbsoluteRgba": targetMetrics.meanAbsoluteRgba,
          "pixelsOver16": targetMetrics.pixelsOver16,
          "outsideRoiErrors": targetMetrics.outsideRoiErrors,
          "changedPixels": targetMetrics.changedPixels,
          "referenceChangedPixels": targetMetrics.referenceChangedPixels
        }
      }

      if animationIndex == 0:
        var base = scene.capture(resources.value, renderer, translationTarget,
          TranslationCanvasWidth)
        var shifted = scene.capture(resources.value, renderer,
          translationTarget, TranslationCanvasWidth,
          spliney.Vec2(x: 100, y: 0))
        verifyTranslation(base, shifted)
        expect(exportImage(base,
          arguments.outputDir / "translation-base.png"),
          "failed to export base translation capture")
        expect(exportImage(shifted,
          arguments.outputDir / "translation-shifted.png"),
          "failed to export shifted translation capture")

      expect(scene.close().isOk, "scene close failed")

    let report = %*{
      "schemaVersion": 1,
      "assetSha256": ExpectedAssetSha,
      "officialRuntimeSha": ExpectedRuntimeSha,
      "backend": "Naylib/Raylib direct rlgl textured triangles",
      "canvas": {"width": CanvasWidth, "height": CanvasHeight},
      "translationPixels": 100,
      "decodeCount": factory.decodeCount,
      "uploadCount": factory.uploadCount,
      "animations": reportAnimations
    }
    writeFile(arguments.outputDir / "capture-metrics.json", report.pretty & "\n")
  finally:
    if translationTarget.texture.id != 0:
      translationTarget = default(RenderTexture2D)
    if target.texture.id != 0:
      target = default(RenderTexture2D)
    if resources.isOk:
      let closed = resources.value.close()
      if not closed.isOk: shutdownError = closed.error.message
    if not factory.isNil:
      if factory.releaseCount != factory.uploadCount:
        shutdownError = "Raylib resources were not released before window close"
    closeWindow()
  expect(shutdownError.len == 0, shutdownError)
  expect(imported.value.close().isOk, "imported file close failed")
  echo "exact Raylib captures and 100-pixel translation verified"

when isMainModule:
  main()
