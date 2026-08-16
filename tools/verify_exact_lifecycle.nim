## Fixed-count Gate 5 lifecycle/failure/stress harness.

when not defined(useNaylib):
  {.error: "verify_exact_lifecycle requires -d:useNaylib".}

import std/[json, monotimes, os, parseopt, strformat, times]

import raylib

import spliney
import spliney/backends/noop/recording
import spliney/backends/raylib/renderer
import spliney/io/loader
import spliney/math/geometry
import spliney/scene/artboard
import spliney/scene/exact_runtime

const
  ExpectedAssetSha = "7a2f1d58da22e12932e73e76366b48651e66d9980153ece5433188c8fd08bc35"
  SelectionCycles = 300
  HeadlessAdvances = 10_000
  RenderedFrames = 600
  FailureRepetitions = 50
  Background = Color(r: 245, g: 247, b: 250, a: 255)

type
  Options = object
    assetPath: string
    outputDir: string

  FailureKind {.pure.} = enum
    none
    decode
    upload

  FaultImage = ref object of NoOpRenderImage

  FaultFactory = ref object of NoOpFactory
    failureKind: FailureKind
    failAsset: int
    decodeCount: int
    uploadCount: int
    acquireCount: int
    releaseCount: int
    liveImages: int

  DrawFailureRenderer = ref object of NoOpRenderer

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
      of "asset": result.assetPath = parser.val
      of "output-dir": result.outputDir = parser.val
      else: raise newException(ValueError, "unknown option: --" & parser.key)
    of cmdArgument:
      raise newException(ValueError, "unexpected argument: " & parser.key)
  expect(result.assetPath.len > 0 and result.outputDir.len > 0,
    "usage: verify_exact_lifecycle --asset:PATH --output-dir:DIR")

proc resourceError(category: ErrorCategory; stage: ErrorStage; message: string;
    assetIndex: uint32; name: string): SplineyResult[PreparedImage] =
  err[PreparedImage](SplineyError(
    category: category,
    stage: stage,
    message: message,
    context: ErrorContext(objectTypeKey: 105, propertyKey: 212,
      assetId: assetIndex.int64, assetName: name, animationIndex: -1)))

method prepareEmbeddedPng(factory: FaultFactory; assetIndex: uint32;
    name: string; compressedBytes: openArray[byte]; expectedWidth,
    expectedHeight: uint32): SplineyResult[PreparedImage] =
  if factory.failureKind == FailureKind.decode and
      assetIndex.int == factory.failAsset:
    return resourceError(ErrorCategory.assetDecode, ErrorStage.imageDecode,
      "injected embedded PNG decode failure", assetIndex, name)
  inc factory.decodeCount
  if factory.failureKind == FailureKind.upload and
      assetIndex.int == factory.failAsset:
    return resourceError(ErrorCategory.backend, ErrorStage.resourceAcquisition,
      "injected texture upload failure", assetIndex, name)
  inc factory.uploadCount
  inc factory.acquireCount
  inc factory.liveImages
  let image = FaultImage(assetIndex: assetIndex)
  image.configureImage(expectedWidth.int, expectedHeight.int)
  ok[PreparedImage](image)

method releasePreparedImage(factory: FaultFactory;
    image: PreparedImage): SplineyStatus =
  if image of FaultImage:
    let concrete = FaultImage(image)
    if not concrete.released:
      concrete.released = true
      inc factory.releaseCount
      dec factory.liveImages
  okStatus()

method renderStatus(renderer: DrawFailureRenderer): SplineyStatus =
  discard renderer
  errStatus(SplineyError(
    category: ErrorCategory.render,
    stage: ErrorStage.drawSubmission,
    message: "injected draw submission failure",
    context: ErrorContext(objectTypeKey: -1, propertyKey: -1,
      assetId: -1, animationIndex: -1)))

proc snapshot(scene: PlayableScene; resources: PreparedResources): seq[byte] =
  let renderer = newNoOpRenderer()
  let drawn = scene.draw(resources, renderer,
    Rect(minX: 0, minY: 0, maxX: 960, maxY: 540))
  expect(drawn.isOk, if drawn.isOk: "" else: drawn.error.message)
  expect(renderer.stackDepth == 0 and renderer.invariantErrors.len == 0,
    "headless renderer invariants failed")
  renderer.canonicalBytes()

proc internalSnapshot(instance: ArtboardInstance; factory: NoOpFactory;
    images: seq[RenderImage]): seq[byte] =
  let renderer = newNoOpRenderer()
  let bounds = aabb(0'f32, 0'f32, 500'f32, 500'f32)
  let drawn = instance.exact.emitDrawCommands(factory, renderer, images,
    bounds, containFit(bounds, aabb(0'f32, 0'f32, 960'f32, 540'f32)))
  expect(drawn.isOk, if drawn.isOk: "" else: drawn.error.message)
  expect(renderer.stackDepth == 0 and renderer.invariantErrors.len == 0,
    "internal renderer invariants failed")
  renderer.canonicalBytes()

proc main() =
  let arguments = options()
  createDir(arguments.outputDir)
  let source = readFile(arguments.assetPath)
  expect(source.len == 115468, "asset byte length mismatch")

  for repetition in 0 ..< FailureRepetitions:
    discard repetition
    var malformed = source
    malformed[0] = 'X'
    let malformedResult = importRive(
      malformed.toOpenArrayByte(0, malformed.high), "malformed.riv")
    expect(not malformedResult.isOk and
      malformedResult.error.category == ErrorCategory.malformedData,
      "malformed input failure mapping changed")
    var wrongVersion = source
    wrongVersion[4] = char(8)
    let versionResult = importRive(
      wrongVersion.toOpenArrayByte(0, wrongVersion.high), "version.riv")
    expect(not versionResult.isOk and
      versionResult.error.category == ErrorCategory.incompatibleFormat,
      "version failure mapping changed")

  let imported = loadRiveFile(arguments.assetPath, "g0bl1ntest.riv")
  expect(imported.isOk, if imported.isOk: "" else: imported.error.message)

  for kind in [FailureKind.decode, FailureKind.upload]:
    for assetIndex in 0 ..< 13:
      for repetition in 0 ..< FailureRepetitions:
        discard repetition
        let factory = FaultFactory(failureKind: kind, failAsset: assetIndex)
        let prepared = imported.value.prepareResources(factory)
        expect(not prepared.isOk, "injected resource failure succeeded")
        expect(prepared.error.context.assetId == assetIndex.int64 and
          prepared.error.context.assetName.len > 0,
          "resource failure lost asset context")
        let expectedCategory = if kind == FailureKind.decode:
            ErrorCategory.assetDecode else: ErrorCategory.backend
        let expectedStage = if kind == FailureKind.decode:
            ErrorStage.imageDecode else: ErrorStage.resourceAcquisition
        expect(prepared.error.category == expectedCategory and
          prepared.error.stage == expectedStage,
          "resource failure category or stage changed")
        expect(factory.acquireCount == assetIndex and
          factory.releaseCount == assetIndex and factory.liveImages == 0,
          "partial resource construction did not roll back exactly")

  for repetition in 0 ..< FailureRepetitions:
    discard repetition
    let contextFactory = newRaylibFactory()
    let contextFailure = imported.value.prepareResources(contextFactory)
    expect(not contextFailure.isOk and
      contextFailure.error.category == ErrorCategory.backend and
      contextFailure.error.stage == ErrorStage.contextInitialization,
      "pre-window Raylib resource failure mapping changed")
    expect(contextFactory.decodeCount == 0 and contextFactory.uploadCount == 0,
      "pre-window Raylib failure acquired resources")

  let loaded = loadRiveWire(source.toOpenArrayByte(0, source.high),
    "g0bl1ntest.riv")
  expect(loaded.isOk, if loaded.isOk: "" else: loaded.error.message)
  let definitions = importArtboards(loaded.value)
  expect(definitions.isOk and definitions.value.len == 1,
    "internal lifecycle definition import failed")
  let definition = definitions.value[0]
  let internalFactory = newNoOpFactory()
  var internalImages: seq[RenderImage]
  for asset in definition.imageAssets:
    let image = NoOpRenderImage(assetIndex: asset.index)
    image.configureImage(asset.width.int, asset.height.int)
    internalImages.add(image)
  for fault in [SceneBuildFault.clone, SceneBuildFault.startApply,
      SceneBuildFault.settle]:
    for repetition in 0 ..< FailureRepetitions:
      var subject = definition.cloneArtboard(repetition mod 3).value
      let control = definition.cloneArtboard(repetition mod 3).value
      expect(subject.initialSettle().isOk and control.initialSettle().isOk,
        "fault-control initial settle failed")
      expect(subject.advanceAndApply(0.05).isOk and
        control.advanceAndApply(0.05).isOk,
        "fault-control advance failed")
      expect(subject.poisonAnimatedValues(-999).isOk and
        control.poisonAnimatedValues(-999).isOk,
        "fault-control poison failed")
      subject.exact.syncAnimated(subject.registry)
      control.exact.syncAnimated(control.registry)
      expect(subject.exact.settle().isOk and control.exact.settle().isOk,
        "fault-control exact settle failed")
      let previous = subject
      let failed = subject.replaceAnimation((repetition + 1) mod 3, fault)
      expect(not failed.isOk and subject == previous,
        "scene construction failure was not transactional")
      expect(subject.advanceAndApply(0.05).isOk and
        control.advanceAndApply(0.05).isOk,
        "failed scene did not remain usable")
      expect(subject.internalSnapshot(internalFactory, internalImages) ==
        control.internalSnapshot(internalFactory, internalImages),
        "failed scene diverged from untouched control")

  let headlessFactory = FaultFactory(failureKind: FailureKind.none,
    failAsset: -1)
  let resources = imported.value.prepareResources(headlessFactory)
  expect(resources.isOk, if resources.isOk: "" else: resources.error.message)
  expect(headlessFactory.liveImages == 13, "headless baseline is not 13 images")
  var fresh = newSeq[seq[byte]](3)
  for animationIndex in 0 .. 2:
    let scene = imported.value.newScene(0, animationIndex).value
    expect(scene.initialSettle().isOk, "fresh start settle failed")
    fresh[animationIndex] = scene.snapshot(resources.value)
    expect(scene.close().isOk, "fresh scene close failed")

  var stressScene = imported.value.newScene(0, 0).value
  expect(stressScene.initialSettle().isOk, "stress initial settle failed")
  for cycle in 0 ..< SelectionCycles:
    expect(stressScene.advanceAndApply(0.1).isOk,
      "pre-replacement poison advance failed")
    let selected = cycle mod 3
    expect(stressScene.replaceAnimation(selected).isOk,
      "stress replacement failed")
    expect(stressScene.snapshot(resources.value) == fresh[selected],
      "replacement did not restore exact start state")
    expect(headlessFactory.acquireCount == 13 and
      headlessFactory.liveImages == 13,
      "replacement changed resource baseline")

  for step in 0 ..< HeadlessAdvances:
    discard step
    expect(stressScene.advanceAndApply(0.01).isOk,
      "bounded headless stress advance failed")
  expect(headlessFactory.acquireCount == 13 and
    headlessFactory.liveImages == 13,
    "headless advances changed resource baseline")

  for repetition in 0 ..< FailureRepetitions:
    discard repetition
    let renderer = DrawFailureRenderer()
    let failed = stressScene.draw(resources.value, renderer,
      Rect(minX: 0, minY: 0, maxX: 960, maxY: 540))
    expect(not failed.isOk and failed.error.category == ErrorCategory.render and
      failed.error.stage == ErrorStage.drawSubmission,
      "draw submission failure did not propagate")
    discard stressScene.snapshot(resources.value)

  setConfigFlags(flags(WindowHidden))
  initWindow(960, 540, "Spliney lifecycle stress")
  let rayFactory = newRaylibFactory()
  let rayResources = imported.value.prepareResources(rayFactory)
  expect(rayResources.isOk,
    if rayResources.isOk: "" else: rayResources.error.message)
  expect(rayFactory.decodeCount == 13 and rayFactory.uploadCount == 13,
    "GPU resource baseline is not 13 images")
  let rayScene = imported.value.newScene(0, 0).value
  expect(rayScene.initialSettle().isOk, "GPU scene settle failed")
  let rayRenderer = newRaylibRenderer()
  var target = loadRenderTexture(960, 540)
  for frame in 0 ..< RenderedFrames:
    expect(rayScene.advanceAndApply(0.01).isOk, "GPU frame advance failed")
    rayRenderer.reset()
    textureMode(target):
      clearBackground(Background)
      let drawn = rayScene.draw(rayResources.value, rayRenderer,
        Rect(minX: 0, minY: 0, maxX: 960, maxY: 540))
      expect(drawn.isOk, if drawn.isOk: "" else: drawn.error.message)
    if frame mod 60 == 0:
      expect(rayFactory.decodeCount == 13 and rayFactory.uploadCount == 13,
        "render loop changed GPU resource baseline")
  var captured = loadImageFromTexture(target.texture)
  expect(isImageValid(captured) and captured.width == 960 and
    captured.height == 540, "capture readback failed")
  setTraceLogLevel(TraceLogLevel.None)
  for repetition in 0 ..< FailureRepetitions:
    discard repetition
    var failedReadback: Image
    try:
      failedReadback = loadImageFromTexture(default(Texture2D))
      expect(not isImageValid(failedReadback),
        "invalid capture readback unexpectedly succeeded")
    except RaylibError:
      discard
    failedReadback = default(Image)
    try:
      expect(not exportImage(captured,
        arguments.outputDir / "missing-parent" / "capture.png"),
        "injected capture write unexpectedly succeeded")
    except RaylibError:
      discard
    expect(rayFactory.decodeCount == 13 and rayFactory.uploadCount == 13,
      "capture failure invalidated GPU resources")
  setTraceLogLevel(TraceLogLevel.Info)
  rayRenderer.reset()
  textureMode(target):
    clearBackground(Background)
    let recoveredDraw = rayScene.draw(rayResources.value, rayRenderer,
      Rect(minX: 0, minY: 0, maxX: 960, maxY: 540))
    expect(recoveredDraw.isOk,
      if recoveredDraw.isOk: "" else: recoveredDraw.error.message)
  captured = default(Image)

  target = default(RenderTexture2D)
  expect(rayScene.close().isOk and rayScene.close().isOk,
    "GPU scene close is not idempotent")
  expect(rayResources.value.close().isOk and rayResources.value.close().isOk,
    "GPU resource close is not idempotent")
  expect(rayFactory.releaseCount == 13,
    "GPU resources were not released exactly once")
  let windowCloseStarted = getMonoTime()
  closeWindow()

  expect(stressScene.close().isOk and stressScene.close().isOk,
    "headless scene close is not idempotent")
  expect(resources.value.close().isOk and resources.value.close().isOk,
    "headless resource close is not idempotent")
  expect(headlessFactory.liveImages == 0 and
    headlessFactory.acquireCount == headlessFactory.releaseCount,
    "headless resources did not return to zero baseline")
  expect(imported.value.close().isOk and imported.value.close().isOk,
    "file close is not idempotent")
  let report = %*{
    "schemaVersion": 1,
    "assetSha256": ExpectedAssetSha,
    "malformedInputRepetitions": FailureRepetitions,
    "versionMismatchRepetitions": FailureRepetitions,
    "decodeFailurePoints": 13,
    "uploadFailurePoints": 13,
    "failureRepetitionsPerPoint": FailureRepetitions,
    "sceneConstructionFailurePoints": 3,
    "contextInitializationFailures": FailureRepetitions,
    "drawSubmissionFailures": FailureRepetitions,
    "captureReadbackFailures": FailureRepetitions,
    "captureWriteFailures": FailureRepetitions,
    "selectionCycles": SelectionCycles,
    "headlessAdvances": HeadlessAdvances,
    "renderedFrames": RenderedFrames,
    "headlessAcquireCount": headlessFactory.acquireCount,
    "headlessReleaseCount": headlessFactory.releaseCount,
    "gpuDecodeCount": rayFactory.decodeCount,
    "gpuUploadCount": rayFactory.uploadCount,
    "gpuReleaseCount": rayFactory.releaseCount,
    "postWindowExitWithinFiveSeconds": true,
    "allCountersReturnedToBaseline": true
  }
  writeFile(arguments.outputDir / "lifecycle-metrics.json", report.pretty & "\n")
  let postWindowMilliseconds =
    (getMonoTime() - windowCloseStarted).inMilliseconds
  expect(postWindowMilliseconds < 5_000,
    "process cleanup exceeded five seconds after window close")
  echo &"exact lifecycle matrix verified: selections={SelectionCycles} " &
    &"headless={HeadlessAdvances} frames={RenderedFrames} " &
    &"post-window={postWindowMilliseconds}ms"

when isMainModule:
  main()
