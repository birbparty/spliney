#!/bin/bash
# Project: spliney — a from-scratch Rive animation runtime in Nim
# Generated: 2026-06-13
#
# Builds the full Beads task graph for spliney: a renderer-agnostic, dependency-light
# core (binary .riv loader -> core object model -> scene-graph dependency solver ->
# linear-animation + state-machine engine, emitting draw commands against an abstract
# Renderer/Factory seam) plus thin boxy (OpenGL/Pixie) and clckr/raylib (naylib) adapters.
#
# Design rules encoded here:
#   * MVP-first, phased: (1) vector playback no-SM -> (2) state machines ->
#     (3) raster assets/meshes -> (5) constraints/nested artboards.
#   * Cross-phase-parallel beads (grounding, tessellation, fixtures, CI, packaging,
#     ADRs, feasibility spike) depend ONLY on setup so `bd ready` shows a wide frontier.
#   * Strict core/renderer separation enforced by a fail-closed purity allowlist.
#   * Wire-format correctness grounded against include/rive/ + dev/defs/ before coding.
#   * Single-owner code-gen bead for the key tables to remove the worst collision point.
#   * Every in-scope phase ends with a runnable demo that GATES phase completion.
#   * Text + scripting/data-binding/audio live behind an OUT-OF-SCOPE gate, off the
#     active ready queue.
#
# Primary reference (read FIRST): docs/reference/rive-runtime-reference.md

set -euo pipefail

# --- preflight ----------------------------------------------------------------
if ! command -v bd >/dev/null 2>&1; then
  echo "error: 'bd' (beads) CLI not found on PATH" >&2
  exit 1
fi

if [ ! -d ".beads" ]; then
  echo "Initializing beads..."
  bd init
fi

echo "Creating spliney task graph..."

# ==============================================================================
# Phase 0 — Setup, ADRs, grounding, infra (cross-phase-parallel: depend on SETUP)
# ==============================================================================

SETUP=$(bd create "Scaffold nimble package + root nim.cfg (--path:src, --mm:orc), srcDir=src" \
  -d "Create spliney.nimble with srcDir=\"src\" and version. Add a committed root nim.cfg with --path:\"src\" (so editor LSP resolves intra-package imports the same way nimble's build does) and --mm:orc (so editor and build agree on the memory model). Create src/spliney.nim stub barrel. Acceptance: nim check --hints:off on a stub module exits 0 AND nimble build produces a (stub) artifact." \
  -p 0 -l setup --silent)

REFDOC=$(bd create "Ensure docs/reference/rive-runtime-reference.md is present and committed" \
  -d "The phased scope, object model, renderer seam and integration notes assume docs/reference/rive-runtime-reference.md exists as the in-repo source-cited reference (every uncertain symbol flagged with a verify-against-include/rive note). Confirm it is committed; if missing, restore/author it from the project planning doc. This is the READ-FIRST artifact every impl bead points at." \
  -p 0 -l docs --silent)
bd dep add $REFDOC $SETUP

ADR_MM=$(bd create "ADR: memory/lifetime model — ORC + rcp<T> mapping" \
  -d "Decide ORC (cycle collector) vs ARC vs manual cycle-breaking. The scene graph has parent/child refs that form cycles, so plain ARC would leak. Map Rive rcp<T> to Nim ref object under ORC; define the Factory-minted-resource lifetime contract and per-frame allocation discipline. Confirm boxy / naylib / raylib_console already build under --mm:orc (clckr ships to 3DS, so likely yes — verify). Blocks the renderer-abstraction work." \
  -p 0 -l adr -t decision --silent)
bd dep add $ADR_MM $SETUP

ADR_AA=$(bd create "ADR: antialiasing strategy (supersample-to-image vs none on console)" \
  -d "boxy/raylib_console have no guaranteed vector AA/MSAA on 3DS/Vita. Decide the AA approach per platform (supersample-to-image for the CPU-raster baseline vs no-AA on console vs desktop MSAA). Drives the tessellation AA bead and the software rasterizer. Document the chosen tradeoff." \
  -p 1 -l adr -t decision --silent)
bd dep add $ADR_AA $SETUP

# --- grounding tasks: each resolves an open wire-format uncertainty and blocks
#     the dependent impl. (BlendMode values, ToC stride = 4 keys/uint32, PathVerb
#     conic skip are ALREADY resolved in the reference — do not re-litigate.)
GROUND_VERSION=$(bd create "Grounding: locate the format major-version constant (it's in file.hpp, not runtime_header.hpp)" \
  -d "Confirm the upstream source + current value of the .riv format major version (7 as of this writing) in include/rive/file.hpp. Deliverable: a single named constant in spliney with a comment citing file.hpp. Blocks the loader's version gate." \
  -p 0 -l grounding --silent)
bd dep add $GROUND_VERSION $REFDOC

GROUND_FIELDTYPES=$(bd create "Grounding: confirm field_types/ filenames + 2-bit backing-type codes" \
  -d "Verify field_types/ filenames in dev/defs and the 2-bit ToC backing-type codes (0=uint/bool, 1=string, 2=float, 3=color). ToC stride is 4 property keys per uint32 (low 8 bits) — already verified, do not change. Blocks the code-gen registry bead." \
  -p 0 -l grounding --silent)
bd dep add $GROUND_FIELDTYPES $REFDOC

GROUND_ENUMS=$(bd create "Grounding: loopValue / interpolationType enum values" \
  -d "Verify exact enum values for loopValue (oneShot/loop/pingPong) and interpolationType (hold/linear/cubic) against dev/defs/include/rive. Blocks the animation interpolation + engine beads." \
  -p 0 -l grounding --silent)
bd dep add $GROUND_ENUMS $REFDOC

GROUND_NOOP=$(bd create "Grounding: no_op_factory / no_op renderer header path" \
  -d "Verify the upstream no_op_factory + no-op renderer header paths/spellings (utils/ scaffolding). Blocks the Renderer/Factory seam + no-op backend beads." \
  -p 0 -l grounding --silent)
bd dep add $GROUND_NOOP $REFDOC

GROUND_SPELLINGS=$(bd create "Grounding: onDependencySolve / m_DependencyOrder / getBool spellings" \
  -d "Confirm exact spellings/signatures of onDependencySolve, m_DependencyOrder, getBool and related dependency-solver + input accessors. Blocks the scene-graph dependency solver and state-machine input beads." \
  -p 0 -l grounding --silent)
bd dep add $GROUND_SPELLINGS $REFDOC

# --- fixtures: .riv is a custom binary, only the Rive editor produces it.
FIXTURES=$(bd create "Acquire & commit vector-only .riv test fixtures (gates ALL tests)" \
  -d "Author from the Rive editor and commit under tests/fixtures/ with provenance/license notes: (a) single rotating rect, (b) gradient fill, (c) clipped shape, (d) simple state machine. .riv cannot be hand-authored — this bead gates every test bead." \
  -p 0 -l fixtures --silent)
bd dep add $FIXTURES $SETUP

# --- infra
CI=$(bd create "CI: build core + unittests + core-purity test (+ 3DS/Vita cross-compile)" \
  -d "GitHub Actions workflow: build the core with the no-op backend, run nim unittests, run spliney's core-purity test, and attempt 3DS (devkitARM/citro3d) + Vita (vitaGL) cross-compiles to catch dependency violations early. Cache nimble deps." \
  -p 1 -l ci --silent)
bd dep add $CI $SETUP

PKG=$(bd create "nimble packaging + versioning metadata" \
  -d "Finalize spliney.nimble: name, version (semver), author, license=MIT, srcDir=src, backend, requires (keep core deps to vmath/bumpy only). Add `nimble test` task wiring. Document install/require usage. Verify `nimble check` passes." \
  -p 1 -l packaging --silent)
bd dep add $PKG $SETUP

LICENSE_HYGIENE=$(bd create "Licensing hygiene: MIT, retain Rive notice for ported code, no branding implying endorsement" \
  -d "Establish the licensing policy: prefer clean-room-from-spec; where code is ported directly from rive-runtime, retain the Rive MIT notice + attribution. Add NOTICE/THIRD_PARTY as needed. Do not use Rive branding in a way implying official endorsement. Reviewers check ported files against this." \
  -p 2 -l docs --silent)
bd dep add $LICENSE_HYGIENE $SETUP

# --- shared math (foundational; needed by scene/anim/tessellation)
MATH=$(bd create "Core math: Mat2D / Vec2D / AABB (vmath/bumpy where portable)" \
  -d "Lightweight, allocation-free transform + geometry math: Mat2D (2x3 affine), Vec2D, AABB. Reuse vmath/bumpy only if they stay portable to 3DS/Vita and within the core-purity allowlist. Reserves src/spliney/math/**, tests/math/**." \
  -p 0 -l core --silent)
bd dep add $MATH $SETUP

# ==============================================================================
# Phase 1 — Core: loader, registry, object model, scene graph, animation,
#           renderer seam + no-op backend (vector playback, NO state machines)
# ==============================================================================

# Single-owner code-gen bead — collision control for the shared key tables.
REGISTRY=$(bd create "Code-gen type/property-key + backing-type tables + CoreRegistry skeleton from dev/defs/*.json" \
  -d "SINGLE-OWNER bead (collision control). Generate the full type-key + property-key + 2-bit backing-type tables and the CoreRegistry-equivalent skeleton from dev/defs/*.json. Downstream object beads must NOT hand-edit this; they add per-class deserialize bodies under src/spliney/core/**. Reserves src/spliney/generated/** (this bead ONLY)." \
  -p 0 -l core --silent)
bd dep add $REGISTRY $GROUND_FIELDTYPES

LOADER=$(bd create "Binary loader: header + ToC (4 keys/uint32) + object stream + unknown-key skip" \
  -d "LE varuint (LEB128) reader; header (RIVE magic, major from named const, minor, fileId); ToC with 2-bit backing types (0=uint/bool,1=string,2=float,3=color), 4 property keys per uint32 (low 8 bits); object instantiation loop via CoreRegistry; forward-compat: skip unknown type+property keys using ToC backing type; backward-compat: fall back to initialValueRuntime defaults for missing properties; reject mismatched major with a clear error. Reserves src/spliney/io/**, tests/io/**." \
  -p 0 -l loader --silent)
bd dep add $LOADER $REGISTRY
bd dep add $LOADER $GROUND_VERSION

# Core-purity guard (define early; acceptance test needs an importable core).
PURITY=$(bd create "Define spliney core-purity allowlist + fail-closed test" \
  -d "Fail-closed allowlist test that permits the core to import only std/*, math (vmath/bumpy), and spliney's own core modules — failing on any other import (no chroma/pixie/raylib/boxy/native). Document which spliney modules are 'pure'. Reserves tests/purity/**." \
  -p 0 -l purity --silent)
bd dep add $PURITY $REGISTRY

PURITY_CLCKR=$(bd create "Acceptance: spliney core importable under clckr's existing allowlist verbatim" \
  -d "Prove spliney's core imports cleanly under clckr's existing tests/game/test_core_purity.nim allowlist (std/*, vmath, bumpy + named modules) — i.e. spliney core introduces no dep (chroma/pixie/etc) that clckr's portable game core forbids. Run against ~/git/birbparty/clckr." \
  -p 1 -l purity,integration --silent)
bd dep add $PURITY_CLCKR $PURITY
bd dep add $PURITY_CLCKR $LOADER

# --- object model (parallelizable; each depends on REGISTRY; keep each <750 LOC)
OBJ_TRANSFORM=$(bd create "Object model: TransformComponent / Node base + world/local transforms" \
  -d "Per-class deserialize bodies for the transform hierarchy base: TransformComponent, Node, world/local Mat2D composition, parent linkage. Reserves src/spliney/core/transform/**, tests/core/transform/**." \
  -p 0 -l core --silent)
bd dep add $OBJ_TRANSFORM $REGISTRY
bd dep add $OBJ_TRANSFORM $MATH

OBJ_SHAPES=$(bd create "Object model: Shape + parametric primitives (Rectangle/Ellipse/Triangle)" \
  -d "Shape container + parametric path sources (Rectangle incl. corner radius, Ellipse, Triangle) producing path geometry. Reserves src/spliney/core/shapes/**, tests/core/shapes/**." \
  -p 0 -l core --silent)
bd dep add $OBJ_SHAPES $OBJ_TRANSFORM

OBJ_PATH=$(bd create "Object model: PointsPath + vertices (straight/cubic) + PathVerb emission" \
  -d "PointsPath + StraightVertex/CubicVertex (mirror/asymmetric/detached) -> RenderPath verbs. PathVerb value 3 (conic) is intentionally skipped — do not emit it. Reserves src/spliney/core/path/**, tests/core/path/**." \
  -p 0 -l core --silent)
bd dep add $OBJ_PATH $OBJ_TRANSFORM

OBJ_PAINT=$(bd create "Object model: Fill/Stroke + SolidColor + Linear/Radial gradients + stops" \
  -d "Paint objects: Fill, Stroke (thickness/cap/join/transformAffectsStroke), SolidColor, LinearGradient, RadialGradient, GradientStop. BlendMode enum values are NON-contiguous — use the reference §5.4 confirmed-exact values, do not infer. Reserves src/spliney/core/paint/**, tests/core/paint/**." \
  -p 0 -l core --silent)
bd dep add $OBJ_PAINT $REGISTRY
bd dep add $OBJ_PAINT $MATH

OBJ_CLIP=$(bd create "Object model: ClippingShape (Phase-1 object; clipPath no-op-with-warning in MVP)" \
  -d "ClippingShape object + source linkage. In the MVP, clipPath is a no-op-with-warning at the render seam (document the visual limitation). Basic clipping geometry is pulled into Phase 2-3 (see clip-basic bead). Reserves src/spliney/core/clip/**." \
  -p 1 -l core --silent)
bd dep add $OBJ_CLIP $OBJ_SHAPES

# --- scene graph + dependency solver
SCENE_SOLVER=$(bd create "Scene graph: topological dependency-sort + dirty/update solver" \
  -d "Build the dependency order (onDependencySolve / m_DependencyOrder equivalent), topological sort of components, dirty flag propagation + update pass. Use the grounded spellings. Reserves src/spliney/scene/**, tests/scene/**." \
  -p 0 -l scene --silent)
bd dep add $SCENE_SOLVER $OBJ_TRANSFORM
bd dep add $SCENE_SOLVER $GROUND_SPELLINGS

SCENE_ARTBOARD=$(bd create "Scene graph: Artboard load + instance + advance + draw order" \
  -d "Artboard parse/instance, attach drawables, build draw order, advance(dt) driving the dependency solver, expose draw(renderer). Reserves src/spliney/scene/artboard/**." \
  -p 0 -l scene --silent)
bd dep add $SCENE_ARTBOARD $SCENE_SOLVER
bd dep add $SCENE_ARTBOARD $OBJ_SHAPES
bd dep add $SCENE_ARTBOARD $OBJ_PATH
bd dep add $SCENE_ARTBOARD $OBJ_PAINT

# --- linear animation engine
ANIM_KEYED=$(bd create "Animation: KeyedObject / KeyedProperty structures + property apply" \
  -d "KeyedObject -> KeyedProperty -> KeyFrame structures; resolve target core object/property and apply interpolated values back through the CoreRegistry property setters. Reserves src/spliney/animation/keyed/**." \
  -p 0 -l anim --silent)
bd dep add $ANIM_KEYED $REGISTRY
bd dep add $ANIM_KEYED $SCENE_SOLVER

ANIM_INTERP=$(bd create "Animation: interpolation (hold / linear / cubic-bezier easing)" \
  -d "KeyFrame interpolators: hold, linear, cubic-bezier (interpolator control points). Use grounded interpolationType enum values. Pure, headless-testable against numeric epsilons. Reserves src/spliney/animation/interp/**." \
  -p 0 -l anim --silent)
bd dep add $ANIM_INTERP $GROUND_ENUMS
bd dep add $ANIM_INTERP $MATH

ANIM_ENGINE=$(bd create "Animation: LinearAnimation engine (loop/pingPong/work-area, time advance, mix)" \
  -d "LinearAnimation instance: fps/duration, work area, loop modes (oneShot/loop/pingPong via grounded loopValue), time advance, keyframe seeking + apply with mix factor. Reserves src/spliney/animation/engine/**." \
  -p 0 -l anim --silent)
bd dep add $ANIM_ENGINE $ANIM_KEYED
bd dep add $ANIM_ENGINE $ANIM_INTERP
bd dep add $ANIM_ENGINE $GROUND_ENUMS

# --- renderer / factory abstraction + no-op backend (the determinism oracle)
RENDER_SEAM=$(bd create "Renderer/Factory seam: 8 pure-virtual ops + RenderPath/Paint/Image/Buffer/Shader" \
  -d "Nim mirror of rive::Renderer (8 pure-virtual ops incl. clipPath) + Factory + RenderPath/RenderPaint/RenderImage/RenderBuffer/RenderShader. Under ORC per the memory ADR. Reserves src/spliney/render/** (seam only)." \
  -p 0 -l render --silent)
bd dep add $RENDER_SEAM $ADR_MM
bd dep add $RENDER_SEAM $GROUND_NOOP

RENDER_NOOP=$(bd create "No-op backend (determinism oracle): records the emitted draw-command stream" \
  -d "no-op Renderer/Factory that records ordered draw commands (no display dependency). This is the cheapest high-value test oracle: advance N frames on a fixed dt sequence, hash the command stream. Reserves src/spliney/backends/noop/**." \
  -p 0 -l render --silent)
bd dep add $RENDER_NOOP $RENDER_SEAM
bd dep add $RENDER_NOOP $GROUND_NOOP

DRAW_EMIT=$(bd create "Draw emission: artboard/shapes/paint/clip -> Renderer command stream" \
  -d "Wire Artboard.draw to emit path/fill/stroke/clip ops against the Renderer seam (clipPath no-op-with-warning in MVP). Reserves src/spliney/render/emit/**." \
  -p 0 -l render --silent)
bd dep add $DRAW_EMIT $RENDER_SEAM
bd dep add $DRAW_EMIT $SCENE_ARTBOARD
bd dep add $DRAW_EMIT $OBJ_PAINT
bd dep add $DRAW_EMIT $OBJ_CLIP

# --- Phase 1 tests (layered oracle; all gated on FIXTURES)
TEST_LOADER_DIFF=$(bd create "Test: loader name+count diff vs rive-code-generator-wip / editor JSON" \
  -d "Parse fixtures and diff object/input/animation NAMES + COUNTS against rive-code-generator-wip metadata (experimental C++ binary, metadata-only — NOT per-frame transforms). Fall back to Rive editor JSON export if that tool won't build. Reserves tests/io/diff/**." \
  -p 1 -l testing,loader --silent)
bd dep add $TEST_LOADER_DIFF $LOADER
bd dep add $TEST_LOADER_DIFF $FIXTURES

TEST_ROUNDTRIP=$(bd create "Test: loader round-trip + edge parsing" \
  -d "Round-trip / structural parser tests over the committed fixtures: object counts, property presence, default fallback, unknown-key skip behavior. Reserves tests/io/roundtrip/**." \
  -p 2 -l testing,loader --silent)
bd dep add $TEST_ROUNDTRIP $LOADER
bd dep add $TEST_ROUNDTRIP $FIXTURES

TEST_FUZZ=$(bd create "Test: loader fuzz harness (random truncation / bit-flip must not crash)" \
  -d "The loader parses untrusted bytes. Nim has no built-in fuzzer — build a harness that randomly truncates/bit-flips valid fixtures and asserts the loader returns an error rather than crashing/looping. Reserves tests/io/fuzz/**." \
  -p 1 -l testing,loader --silent)
bd dep add $TEST_FUZZ $LOADER
bd dep add $TEST_FUZZ $FIXTURES

TEST_ANIM_NUMERIC=$(bd create "Test: animation numeric cross-check vs rive-flutter (<=0.13.x)" \
  -d "Port a handful of animation cases from the pure-Dart rive-flutter <=0.13.x reference and assert frame-by-frame transform/opacity values within an epsilon — the only GC'd reference with hand-written math to cross-check. Reserves tests/animation/numeric/**." \
  -p 1 -l testing,anim --silent)
bd dep add $TEST_ANIM_NUMERIC $ANIM_ENGINE
bd dep add $TEST_ANIM_NUMERIC $FIXTURES

TEST_NOOP_HASH=$(bd create "Test: no-op draw-stream determinism hash (advance N frames, hash commands)" \
  -d "Advance fixtures N frames on a fixed dt sequence against the no-op backend and hash the emitted draw-command stream; assert stability. Zero display dependency. Belongs in Phase 1. Reserves tests/render/determinism/**." \
  -p 0 -l testing,render --silent)
bd dep add $TEST_NOOP_HASH $RENDER_NOOP
bd dep add $TEST_NOOP_HASH $DRAW_EMIT
bd dep add $TEST_NOOP_HASH $ANIM_ENGINE
bd dep add $TEST_NOOP_HASH $FIXTURES

# --- Phase 1 demo + completion milestone
DEMO_P1=$(bd create "DEMO (Phase 1): headless vector-animation playback end-to-end" \
  -d "Runnable demo: load a fixture, advance the animation, render through the no-op backend (and the software rasterizer to a PNG once available). Proves vector playback end-to-end with no state machines. Reserves examples/p1_vector/**." \
  -p 0 -l integration --silent)
bd dep add $DEMO_P1 $DRAW_EMIT
bd dep add $DEMO_P1 $ANIM_ENGINE
bd dep add $DEMO_P1 $RENDER_NOOP

PHASE1_DONE=$(bd create "MILESTONE: Phase 1 complete — vector playback (no SM)" \
  -d "Gate: Phase 1 is not done until its demo runs AND the layered Phase-1 oracles are green (no-op determinism hash, animation numeric cross-check, loader name/count diff) AND core purity holds." \
  -p 0 -l milestone --silent)
bd dep add $PHASE1_DONE $DEMO_P1
bd dep add $PHASE1_DONE $TEST_NOOP_HASH
bd dep add $PHASE1_DONE $TEST_ANIM_NUMERIC
bd dep add $PHASE1_DONE $TEST_LOADER_DIFF
bd dep add $PHASE1_DONE $PURITY

# ==============================================================================
# Tessellation epic — mostly pure geometry (geometry-in -> triangles-out).
# Cross-phase-parallel: depends only on MATH (+ AA ADR). Headless-testable.
# ==============================================================================
TESS_FLATTEN=$(bd create "Tessellation: cubic/quad flattening with adaptive tolerance" \
  -d "Flatten cubic + quadratic beziers to polylines with adaptive (flatness-tolerance) subdivision. Pure, headless-testable. Reserves src/spliney/render/tess/flatten/**." \
  -p 1 -l render --silent)
bd dep add $TESS_FLATTEN $MATH

TESS_FILL_NZ=$(bd create "Tessellation: nonZero fill triangulation" \
  -d "Triangulate filled contours with the nonZero winding rule (geometry-in -> triangles-out). Pure, headless-testable against vertex/area oracles. Reserves src/spliney/render/tess/fill/**." \
  -p 1 -l render --silent)
bd dep add $TESS_FILL_NZ $TESS_FLATTEN

TESS_FILL_EO=$(bd create "Tessellation: evenOdd fill triangulation" \
  -d "evenOdd winding-rule fill triangulation variant. Pure, headless-testable. Reserves src/spliney/render/tess/fill/**." \
  -p 1 -l render --silent)
bd dep add $TESS_FILL_EO $TESS_FLATTEN

TESS_STROKE=$(bd create "Tessellation: stroke->fill expansion with joins (miter/round/bevel)" \
  -d "Expand strokes to fillable geometry with miter/round/bevel joins. rive-rs shipped strokes-all-round — this is genuinely hard; keep it pure + headless-testable. Reserves src/spliney/render/tess/stroke/**." \
  -p 1 -l render --silent)
bd dep add $TESS_STROKE $TESS_FLATTEN

TESS_CAPS=$(bd create "Tessellation: stroke caps (butt/round/square) + miter limit" \
  -d "Line caps (butt/round/square) and miter-limit handling on top of stroke expansion. Pure, headless-testable. Reserves src/spliney/render/tess/stroke/**." \
  -p 1 -l render --silent)
bd dep add $TESS_CAPS $TESS_STROKE

TESS_AA=$(bd create "Tessellation: antialiasing implementation per AA ADR" \
  -d "Implement the AA approach chosen in the AA ADR (e.g. supersample-to-image for the CPU-raster baseline; none on console). Reserves src/spliney/render/tess/aa/**." \
  -p 2 -l render --silent)
bd dep add $TESS_AA $ADR_AA
bd dep add $TESS_AA $TESS_FILL_NZ

# --- software rasterizer: triangles -> RGBA image (offscreen golden + console baseline)
SOFT_RASTER=$(bd create "Software rasterizer: triangles -> RGBA image buffer (offscreen)" \
  -d "CPU rasterizer that fills tessellated triangles (with gradients/solid + AA per ADR) into an RGBA buffer. Powers the offscreen golden-image oracle AND the console CPU-rasterize-to-texture adapter baseline. Reserves src/spliney/render/raster/**." \
  -p 1 -l render --silent)
bd dep add $SOFT_RASTER $TESS_FILL_NZ
bd dep add $SOFT_RASTER $TESS_STROKE
bd dep add $SOFT_RASTER $MATH

GOLDEN_SOFT=$(bd create "Test: golden-image diff via software rasterizer (no GPU)" \
  -d "Render fixtures through the software rasterizer to PNG and diff against checked-in references with per-pixel tolerance + diff-artifact upload. The automatable render-layer oracle, independent of any GPU backend. Reserves tests/render/golden/**, tests/fixtures/golden/**." \
  -p 1 -l testing,render,fixtures --silent)
bd dep add $GOLDEN_SOFT $SOFT_RASTER
bd dep add $GOLDEN_SOFT $DRAW_EMIT
bd dep add $GOLDEN_SOFT $FIXTURES

# ==============================================================================
# Backend feasibility spike + adapters (premise NOT yet proven on console).
# The spike BLOCKS all adapter work.
# ==============================================================================
SPIKE=$(bd create "SPIKE: resolve 'no triangle/mesh primitive on console' for boxy + raylib" \
  -d "boxy has no mesh API + its raw-GL escape hatch is desktop-only; raylib_console rlgl availability is unconfirmed. Decide per platform: (a) extend the host renderer (e.g. add drawMesh to boxy — a boxy-repo change, tracked as a dependency) for desktop tessellated triangles, vs (b) CPU-rasterize-to-texture baseline (boxy addImage / raylib DrawTexture) for console. BLOCKS all adapter beads. Do not let the graph imply the tessellated path is solved on 3DS/Vita." \
  -p 0 -l render --silent)
bd dep add $SPIKE $SETUP

BOXY_DRAWMESH=$(bd create "boxy upstream: add drawMesh (arbitrary triangles) capability — if spike picks tessellated desktop" \
  -d "Conditional on the spike choosing the tessellated-desktop route for boxy: add a drawMesh/arbitrary-triangle primitive to ~/git/boxy (src/boxy.nim + backend_interface.nim) OR author raw-GL in the adapter (desktop-only). Tracked as an upstream-boxy dependency of the boxy tessellated adapter." \
  -p 2 -l backend-boxy --silent)
bd dep add $BOXY_DRAWMESH $SPIKE

ADAPTER_BOXY_RASTER=$(bd create "boxy adapter: CPU-rasterize-to-texture (console baseline)" \
  -d "boxy backend route (b): render via the software rasterizer to an image, upload with boxy addImage, draw as a textured quad. Console baseline; also works desktop. Importable without raylib. Reserves src/spliney/backends/boxy/**, tests/backends/boxy/**." \
  -p 1 -l backend-boxy --silent)
bd dep add $ADAPTER_BOXY_RASTER $SPIKE
bd dep add $ADAPTER_BOXY_RASTER $RENDER_SEAM
bd dep add $ADAPTER_BOXY_RASTER $SOFT_RASTER

ADAPTER_BOXY_TESS=$(bd create "boxy adapter: tessellated triangles (desktop only)" \
  -d "boxy backend route (a): emit tessellated fills/strokes via boxy drawMesh (or raw GL). Desktop only. Reserves src/spliney/backends/boxy/**." \
  -p 2 -l backend-boxy --silent)
bd dep add $ADAPTER_BOXY_TESS $SPIKE
bd dep add $ADAPTER_BOXY_TESS $RENDER_SEAM
bd dep add $ADAPTER_BOXY_TESS $TESS_FILL_NZ
bd dep add $ADAPTER_BOXY_TESS $TESS_STROKE
bd dep add $ADAPTER_BOXY_TESS $BOXY_DRAWMESH

ADAPTER_RAYLIB_RASTER=$(bd create "clckr/raylib adapter: CPU-rasterize-to-texture (console baseline)" \
  -d "raylib (naylib) backend route (b): software-raster to image -> raylib texture -> DrawTexture. MUST be importable without boxy. Wires into clckr's render seam (src/game/render.nim) at the raylib edge (platform.nim/raylib_api.nim). Reserves src/spliney/backends/raylib/**, tests/backends/raylib/**." \
  -p 1 -l backend-raylib --silent)
bd dep add $ADAPTER_RAYLIB_RASTER $SPIKE
bd dep add $ADAPTER_RAYLIB_RASTER $RENDER_SEAM
bd dep add $ADAPTER_RAYLIB_RASTER $SOFT_RASTER

ADAPTER_RAYLIB_TESS=$(bd create "clckr/raylib adapter: tessellated triangles via rlgl (desktop; if available)" \
  -d "raylib backend route (a): emit tessellated triangles via rlgl (availability unconfirmed — gated by spike). Desktop. Importable without boxy. Reserves src/spliney/backends/raylib/**." \
  -p 2 -l backend-raylib --silent)
bd dep add $ADAPTER_RAYLIB_TESS $SPIKE
bd dep add $ADAPTER_RAYLIB_TESS $RENDER_SEAM
bd dep add $ADAPTER_RAYLIB_TESS $TESS_FILL_NZ
bd dep add $ADAPTER_RAYLIB_TESS $TESS_STROKE

GOLDEN_BOXY=$(bd create "Test: golden-image diff for the boxy adapter (offscreen FBO/EGL)" \
  -d "Render a known fixture via the boxy adapter to an offscreen FBO (EGL) -> PNG, diff vs reference with per-pixel tolerance. 'Builds' is not 'works' — this is the boxy verification bar. Reserves tests/backends/boxy/golden/**." \
  -p 2 -l testing,backend-boxy --silent)
bd dep add $GOLDEN_BOXY $ADAPTER_BOXY_RASTER
bd dep add $GOLDEN_BOXY $FIXTURES

GOLDEN_RAYLIB=$(bd create "Test: golden-image diff for the raylib adapter (offscreen)" \
  -d "Render a known fixture via the raylib adapter to an offscreen target -> PNG, diff vs reference with per-pixel tolerance. raylib verification bar. Reserves tests/backends/raylib/golden/**." \
  -p 2 -l testing,backend-raylib --silent)
bd dep add $GOLDEN_RAYLIB $ADAPTER_RAYLIB_RASTER
bd dep add $GOLDEN_RAYLIB $FIXTURES

# --- performance / allocation discipline for the 3DS/Vita hot path
PERF_HOTPATH=$(bd create "Resource discipline: no per-frame heap churn in advance/draw hot path" \
  -d "Pre-size + reuse buffers, cap tessellation cost, keep the core static footprint small for 3DS/Vita. Audit + document every allocation in the advance/draw loop; add a regression check on allocation counts where feasible. Reserves docs/perf + targeted refactors." \
  -p 2 -l render,core --silent)
bd dep add $PERF_HOTPATH $DRAW_EMIT
bd dep add $PERF_HOTPATH $ANIM_ENGINE
bd dep add $PERF_HOTPATH $TESS_FILL_NZ

# ==============================================================================
# Phase 2 — State machines (+ basic clipping pulled forward)
# ==============================================================================
SM_INPUTS=$(bd create "State machine: Bool/Number/Trigger inputs" \
  -d "StateMachineInput types (Bool, Number, Trigger) with getBool/getNumber/fire accessors (use grounded spellings). Reserves src/spliney/statemachine/inputs/**." \
  -p 1 -l statemachine --silent)
bd dep add $SM_INPUTS $SCENE_ARTBOARD
bd dep add $SM_INPUTS $GROUND_SPELLINGS

SM_TRANSITIONS=$(bd create "State machine: states + transitions + conditions" \
  -d "AnimationState/AnyState/EntryState/ExitState, transitions with conditions (input comparisons), duration/exit-time. Reserves src/spliney/statemachine/states/**." \
  -p 1 -l statemachine --silent)
bd dep add $SM_TRANSITIONS $SM_INPUTS
bd dep add $SM_TRANSITIONS $ANIM_ENGINE

SM_LAYERS=$(bd create "State machine: layers + blend states (1D/additive)" \
  -d "Layer stack with independent current/transition state, blend states (1D blend, additive) mixing multiple animations. Reserves src/spliney/statemachine/layers/**." \
  -p 1 -l statemachine --silent)
bd dep add $SM_LAYERS $SM_TRANSITIONS

SM_ENGINE=$(bd create "State machine: instance advance + input application + events" \
  -d "StateMachineInstance.advance(dt): apply inputs, evaluate transitions per layer, mix animations, fire events/reported events. Reserves src/spliney/statemachine/engine/**." \
  -p 1 -l statemachine --silent)
bd dep add $SM_ENGINE $SM_LAYERS

CLIP_BASIC=$(bd create "Rendering: basic path/rect clipping (replaces MVP no-op, Phase 2-3)" \
  -d "Implement basic path/rect clipping at the render seam (replacing the MVP no-op-with-warning). Leave nested-artboard clip + advanced refinements for Phase 5. Reserves src/spliney/render/clip/**." \
  -p 1 -l render --silent)
bd dep add $CLIP_BASIC $OBJ_CLIP
bd dep add $CLIP_BASIC $DRAW_EMIT
bd dep add $CLIP_BASIC $TESS_FILL_NZ

TEST_SM=$(bd create "Test: state-machine behavior (input -> transition -> transform)" \
  -d "Drive inputs on the state-machine fixture and assert resulting transitions/transforms via the no-op determinism hash + numeric checks. Reserves tests/statemachine/**." \
  -p 1 -l testing,statemachine --silent)
bd dep add $TEST_SM $SM_ENGINE
bd dep add $TEST_SM $FIXTURES

DEMO_P2=$(bd create "DEMO (Phase 2): interactive state-machine playback" \
  -d "Runnable demo driving state-machine inputs and rendering through an adapter (or software raster -> PNG sequence). Reserves examples/p2_statemachine/**." \
  -p 1 -l integration --silent)
bd dep add $DEMO_P2 $SM_ENGINE
bd dep add $DEMO_P2 $DRAW_EMIT

PHASE2_DONE=$(bd create "MILESTONE: Phase 2 complete — state machines + basic clipping" \
  -d "Gate: state-machine engine + tests green, basic clipping implemented, Phase-2 demo runs. Depends on Phase 1." \
  -p 1 -l milestone --silent)
bd dep add $PHASE2_DONE $PHASE1_DONE
bd dep add $PHASE2_DONE $DEMO_P2
bd dep add $PHASE2_DONE $TEST_SM
bd dep add $PHASE2_DONE $CLIP_BASIC

# ==============================================================================
# Phase 3 — Raster assets / meshes (heavy decode behind Factory.decode* seam)
# ==============================================================================
ASSET_SEAM=$(bd create "Assets: Factory.decode* seam + asset references (in-band + out-of-band)" \
  -d "Image asset references in the .riv (embedded + referenced/out-of-band), routed through Factory.decode* so heavy raster decoders stay OUT of the core. Reserves src/spliney/core/assets/**." \
  -p 2 -l core,render --silent)
bd dep add $ASSET_SEAM $RENDER_SEAM
bd dep add $ASSET_SEAM $LOADER

RASTER_DECODE=$(bd create "Assets: optional raster decode module (png/jpeg/webp) behind Factory.decode*" \
  -d "OPTIONAL, non-core module implementing Factory.decode* via png/jpeg/webp decoders. Must never be imported by the core path (no libpng/jpeg in core). Reserves src/spliney/decode/**." \
  -p 3 -l render --silent)
bd dep add $RASTER_DECODE $ASSET_SEAM

MESH=$(bd create "Rendering: vertex meshes (Mesh, vertices, bone weights) + render mesh op" \
  -d "Deformable vertex meshes: Mesh + MeshVertex + bone weights -> render mesh op (textured triangles). Reserves src/spliney/core/mesh/**, src/spliney/render/mesh/**." \
  -p 2 -l render,core --silent)
bd dep add $MESH $DRAW_EMIT
bd dep add $MESH $OBJ_PATH

TEST_RASTER_GOLDEN=$(bd create "Test: golden-image diff for image fills + meshes" \
  -d "Golden-image diffs for image-fill and mesh fixtures through the software rasterizer/adapters. Reserves tests/render/golden/raster/**." \
  -p 2 -l testing,render --silent)
bd dep add $TEST_RASTER_GOLDEN $MESH
bd dep add $TEST_RASTER_GOLDEN $ASSET_SEAM
bd dep add $TEST_RASTER_GOLDEN $FIXTURES

DEMO_P3=$(bd create "DEMO (Phase 3): raster image + mesh playback" \
  -d "Runnable demo rendering a fixture with an image fill + a deformable mesh. Reserves examples/p3_raster/**." \
  -p 2 -l integration --silent)
bd dep add $DEMO_P3 $MESH
bd dep add $DEMO_P3 $ASSET_SEAM

PHASE3_DONE=$(bd create "MILESTONE: Phase 3 complete — raster assets + meshes" \
  -d "Gate: asset seam + mesh rendering + golden tests green, Phase-3 demo runs. Depends on Phase 2." \
  -p 2 -l milestone --silent)
bd dep add $PHASE3_DONE $PHASE2_DONE
bd dep add $PHASE3_DONE $DEMO_P3
bd dep add $PHASE3_DONE $TEST_RASTER_GOLDEN

# ==============================================================================
# Phase 5 — Constraints / nested artboards (note: prompt intentionally skips "4")
# ==============================================================================
CONSTRAINTS=$(bd create "Constraints: IK / distance / translation / rotation / scale / transform" \
  -d "Constraint objects integrated into the dependency solver (IK, distance, translation, rotation, scale, transform). Reserves src/spliney/core/constraints/**." \
  -p 2 -l core,scene --silent)
bd dep add $CONSTRAINTS $SCENE_SOLVER
bd dep add $CONSTRAINTS $OBJ_TRANSFORM

NESTED_ARTBOARD=$(bd create "Scene graph: nested artboards" \
  -d "NestedArtboard + nested inputs/animations; instance + advance + draw recursion. Reserves src/spliney/scene/nested/**." \
  -p 2 -l scene --silent)
bd dep add $NESTED_ARTBOARD $SCENE_ARTBOARD
bd dep add $NESTED_ARTBOARD $CLIP_BASIC

CLIP_ADVANCED=$(bd create "Rendering: nested-artboard clip + advanced clip refinements (Phase 5)" \
  -d "Nested-artboard clipping and advanced clip refinements layered on basic clipping. This is the ONLY clip work that belongs in Phase 5. Reserves src/spliney/render/clip/**." \
  -p 2 -l render --silent)
bd dep add $CLIP_ADVANCED $CLIP_BASIC
bd dep add $CLIP_ADVANCED $NESTED_ARTBOARD

TEST_CONSTRAINTS=$(bd create "Test: constraints + nested-artboard behavior" \
  -d "Numeric + no-op-hash + golden tests for constraints and nested artboards. Reserves tests/core/constraints/**, tests/scene/nested/**." \
  -p 2 -l testing --silent)
bd dep add $TEST_CONSTRAINTS $CONSTRAINTS
bd dep add $TEST_CONSTRAINTS $NESTED_ARTBOARD
bd dep add $TEST_CONSTRAINTS $FIXTURES

DEMO_P5=$(bd create "DEMO (Phase 5): constrained + nested-artboard scene" \
  -d "Runnable demo exercising a constraint and a nested artboard with clipping. Reserves examples/p5_constraints/**." \
  -p 2 -l integration --silent)
bd dep add $DEMO_P5 $CONSTRAINTS
bd dep add $DEMO_P5 $NESTED_ARTBOARD
bd dep add $DEMO_P5 $CLIP_ADVANCED

PHASE5_DONE=$(bd create "MILESTONE: Phase 5 complete — constraints + nested artboards" \
  -d "Gate: constraints + nested artboards + advanced clip + tests green, Phase-5 demo runs. Depends on Phase 3." \
  -p 2 -l milestone --silent)
bd dep add $PHASE5_DONE $PHASE3_DONE
bd dep add $PHASE5_DONE $DEMO_P5
bd dep add $PHASE5_DONE $TEST_CONSTRAINTS

# ==============================================================================
# Host integration + consumption (real deliverables — wire spliney into both hosts)
# ==============================================================================
INT_CLCKR=$(bd create "Integration: require/import spliney into clckr at the raylib edge + Rive demo" \
  -d "Add spliney as a dependency of ~/git/birbparty/clckr, wire the raylib adapter at the render seam (src/game/render.nim) without violating the core-purity allowlist, and ship a Rive demo in clckr. Keep clckr's test_core_purity.nim GREEN." \
  -p 2 -l integration,backend-raylib --silent)
bd dep add $INT_CLCKR $ADAPTER_RAYLIB_RASTER
bd dep add $INT_CLCKR $DEMO_P1
bd dep add $INT_CLCKR $PURITY_CLCKR

INT_BOXY=$(bd create "Integration: add a spliney demo under boxy/examples" \
  -d "Add a spliney Rive demo under ~/git/boxy examples using the boxy adapter. Reserves boxy/examples/spliney_*." \
  -p 2 -l integration,backend-boxy --silent)
bd dep add $INT_BOXY $ADAPTER_BOXY_RASTER
bd dep add $INT_BOXY $DEMO_P1

# --- usage docs (after the first end-to-end demo proves the API shape)
DOCS_USAGE=$(bd create "Docs: usage guide (load/advance/render) + API + phase/scope status" \
  -d "Document the public API (load .riv, advance, render through a backend), the core-purity contract, and current phase/scope status. Point readers at docs/reference/rive-runtime-reference.md. Reserves docs/usage/**." \
  -p 2 -l docs --silent)
bd dep add $DOCS_USAGE $DEMO_P1
bd dep add $DOCS_USAGE $PKG

# ==============================================================================
# OUT-OF-SCOPE / FUTURE appendix — kept OFF the active `bd ready` queue by a
# gate bead that is never closed in the current graph. These are deferrable
# native-dep universes, not current work.
# ==============================================================================
FUTURE_GATE=$(bd create "OUT-OF-SCOPE GATE — do not start (keeps deferred work off bd ready)" \
  -d "Tracking gate for deferred work that violates the no-heavy-deps/console constraint or is likely out of scope. Children depend on this and so never surface in bd ready. Do NOT close to 'unlock' them — promote a child into the active graph deliberately if/when scope changes." \
  -p 4 -l future --silent)
bd dep add $FUTURE_GATE $SETUP

FUTURE_TEXT=$(bd create "FUTURE: text rendering (HarfBuzz/SheenBidi) — different dependency universe" \
  -d "Text layout/shaping needs HarfBuzz + SheenBidi, which violate the no-heavy-deps/console constraint. Deferred behind optional modules / Factory seam. Out of the active graph." \
  -p 4 -l future --silent)
bd dep add $FUTURE_TEXT $FUTURE_GATE

FUTURE_SCRIPTING=$(bd create "FUTURE: scripting" \
  -d "Rive scripting support. Likely out of scope; deferred." \
  -p 4 -l future --silent)
bd dep add $FUTURE_SCRIPTING $FUTURE_GATE

FUTURE_DATABIND=$(bd create "FUTURE: data binding" \
  -d "View-model / data-binding support. Likely out of scope; deferred." \
  -p 4 -l future --silent)
bd dep add $FUTURE_DATABIND $FUTURE_GATE

FUTURE_AUDIO=$(bd create "FUTURE: audio events / playback" \
  -d "Audio asset playback. Likely out of scope; deferred." \
  -p 4 -l future --silent)
bd dep add $FUTURE_AUDIO $FUTURE_GATE

echo ""
echo "spliney task graph created."
echo "  bd ready        # unblocked work frontier (setup, ADRs, grounding, fixtures, tessellation, spike, math, CI)"
echo "  bd dep tree     # inspect dependencies"
echo "  bd dep cycles   # confirm acyclic"
