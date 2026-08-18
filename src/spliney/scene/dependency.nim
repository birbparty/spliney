## Deterministic dependency sorting and dirty-component evaluation.

import std/tables

import spliney/errors

type
  ComponentDirt* = distinct uint16

const
  DirtNone* = ComponentDirt(0)
  DirtCollapsed* = ComponentDirt(1'u16 shl 0)
  DirtDependents* = ComponentDirt(1'u16 shl 1)
  DirtComponents* = ComponentDirt(1'u16 shl 2)
  DirtDrawOrder* = ComponentDirt(1'u16 shl 3)
  DirtPath* = ComponentDirt(1'u16 shl 4)
  DirtSkin* = DirtPath
  DirtVertices* = ComponentDirt(1'u16 shl 5)
  DirtTransform* = ComponentDirt(1'u16 shl 6)
  DirtWorldTransform* = ComponentDirt(1'u16 shl 7)
  DirtRenderOpacity* = ComponentDirt(1'u16 shl 8)
  DirtPaint* = ComponentDirt(1'u16 shl 9)
  DirtStops* = ComponentDirt(1'u16 shl 10)
  DirtLayoutStyle* = ComponentDirt(1'u16 shl 11)
  DirtBindings* = ComponentDirt(1'u16 shl 12)
  DirtNSlicer* = ComponentDirt(1'u16 shl 13)
  DirtScriptUpdate* = ComponentDirt(1'u16 shl 14)
  DirtClipping* = ComponentDirt(1'u16 shl 15)
  DirtFilthy* = ComponentDirt(0xfffe'u16)

proc `or`*(left, right: ComponentDirt): ComponentDirt {.inline.} =
  ComponentDirt(uint16(left) or uint16(right))

proc `and`*(left, right: ComponentDirt): ComponentDirt {.inline.} =
  ComponentDirt(uint16(left) and uint16(right))

proc `not`*(value: ComponentDirt): ComponentDirt {.inline.} =
  ComponentDirt(not uint16(value))

proc `==`*(left, right: ComponentDirt): bool {.inline.} =
  uint16(left) == uint16(right)

proc containsAll*(value, flags: ComponentDirt): bool {.inline.} =
  (value and flags) == flags

proc containsAny*(value, flags: ComponentDirt): bool {.inline.} =
  (value and flags) != DirtNone

type
  DependencySolver* = ref object
    order*: seq[DependencyComponent]
    maxSteps*: uint32
    pending: bool
    updating: bool
    currentDepth: int

  DependencyComponent* = ref object
    objectId*: uint32
    graphOrder*: uint32
    dependents*: seq[DependencyComponent]
    dirt*: ComponentDirt
    updateHook*: proc(component: DependencyComponent;
      dirt: ComponentDirt) {.closure.}
    onDirtyHook*: proc(component: DependencyComponent;
      dirt: ComponentDirt) {.closure.}
    solver: DependencySolver

proc dependencyError(message: string; objectId = 0'u32;
    stage = ErrorStage.referenceResolution): SplineyError =
  SplineyError(
    category: ErrorCategory.scene,
    stage: stage,
    message: message,
    context: ErrorContext(
      label: $objectId,
      objectTypeKey: -1,
      propertyKey: -1,
      assetId: -1,
      animationIndex: -1))

proc newDependencyComponent*(objectId: uint32;
    updateHook: proc(component: DependencyComponent;
      dirt: ComponentDirt) {.closure.} = nil;
    onDirtyHook: proc(component: DependencyComponent;
      dirt: ComponentDirt) {.closure.} = nil;
    initialDirt = DirtFilthy): DependencyComponent =
  DependencyComponent(
    objectId: objectId,
    dirt: initialDirt,
    updateHook: updateHook,
    onDirtyHook: onDirtyHook)

proc newDependencySolver*(maxSteps = 100'u32): DependencySolver =
  DependencySolver(maxSteps: maxSteps, currentDepth: -1)

proc addDependent*(component, dependent: DependencyComponent): bool =
  ## Adds a prerequisite -> dependent edge, preserving insertion order.
  if component.isNil or dependent.isNil:
    return false
  for existing in component.dependents:
    if existing == dependent:
      return false
  component.dependents.add(dependent)
  true

proc sortDependencies*(solver: DependencySolver;
    roots: openArray[DependencyComponent]): SplineyStatus =
  ## Mirrors the pinned runtime's DFS over dependents and prepend-on-finish.
  ## The existing order remains usable if the proposed topology is invalid.
  if solver.isNil:
    return errStatus(dependencyError("nil dependency solver"))

  var marks = initTable[pointer, uint8]()
  var sorted: seq[DependencyComponent]
  var failure = dependencyError("dependency cycle")

  proc visit(component: DependencyComponent): bool =
    if component.isNil:
      failure = dependencyError("nil dependency component")
      return false
    let identity = cast[pointer](component)
    case marks.getOrDefault(identity)
    of 1:
      failure = dependencyError("dependency cycle", component.objectId)
      return false
    of 2:
      return true
    else:
      discard
    marks[identity] = 1
    for dependent in component.dependents:
      if not visit(dependent):
        return false
    marks[identity] = 2
    sorted.insert(component, 0)
    true

  for root in roots:
    if not visit(root):
      return errStatus(failure)

  for component in sorted:
    if not component.solver.isNil and component.solver != solver:
      return errStatus(dependencyError(
        "component belongs to another dependency solver", component.objectId))

  for component in solver.order:
    if component.solver == solver:
      component.solver = nil
  solver.order = sorted
  solver.pending = false
  for index, component in solver.order:
    component.solver = solver
    component.graphOrder = index.uint32
    if component.dirt != DirtNone:
      solver.pending = true
  okStatus()

proc addDirt*(component: DependencyComponent; value: ComponentDirt;
    recurse = false): bool =
  if component.isNil or value == DirtNone or component.dirt.containsAll(value):
    return false

  component.dirt = component.dirt or value
  if not component.onDirtyHook.isNil:
    component.onDirtyHook(component, component.dirt)

  let solver = component.solver
  if not solver.isNil:
    solver.pending = true
    if solver.updating and component.graphOrder.int < solver.currentDepth:
      solver.currentDepth = component.graphOrder.int

  if recurse:
    for dependent in component.dependents:
      discard dependent.addDirt(value, true)
  true

proc updateComponents*(solver: DependencySolver): SplineyResult[bool] =
  if solver.isNil:
    return err[bool](dependencyError("nil dependency solver",
      stage = ErrorStage.frameAdvance))
  if not solver.pending:
    return ok(false)
  if solver.maxSteps == 0:
    return err[bool](dependencyError("dependency update did not settle",
      stage = ErrorStage.frameAdvance))

  solver.updating = true
  var steps = 0'u32
  while solver.pending and steps < solver.maxSteps:
    solver.pending = false
    for index, component in solver.order:
      solver.currentDepth = index
      let dirt = component.dirt
      if dirt == DirtNone or dirt.containsAny(DirtCollapsed):
        continue
      component.dirt = DirtNone
      if not component.updateHook.isNil:
        component.updateHook(component, dirt)
      if solver.currentDepth < index:
        break
    inc steps
  solver.updating = false
  solver.currentDepth = -1

  if solver.pending:
    return err[bool](dependencyError("dependency update did not settle",
      stage = ErrorStage.frameAdvance))
  ok(true)
