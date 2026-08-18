import std/unittest

import spliney/errors
import spliney/scene/dependency

suite "scene dependency solver":
  test "sort is deterministic and places prerequisites before dependents":
    let root = newDependencyComponent(1)
    let left = newDependencyComponent(2)
    let right = newDependencyComponent(3)
    let leaf = newDependencyComponent(4)
    check root.addDependent(left)
    check root.addDependent(right)
    check left.addDependent(leaf)
    check not root.addDependent(left)

    let solver = newDependencySolver()
    require solver.sortDependencies([root]).isOk
    check solver.order == @[root, right, left, leaf]
    for index, component in solver.order:
      check component.graphOrder == index.uint32

  test "cycles fail structurally without replacing a valid order":
    let root = newDependencyComponent(1)
    let child = newDependencyComponent(2)
    discard root.addDependent(child)
    let solver = newDependencySolver()
    require solver.sortDependencies([root]).isOk
    let previous = solver.order

    discard child.addDependent(root)
    let cycle = solver.sortDependencies([root])
    check not cycle.isOk
    check cycle.error.category == ErrorCategory.scene
    check cycle.error.stage == ErrorStage.referenceResolution
    check cycle.error.message == "dependency cycle"
    check solver.order == previous

  test "recursive dirt propagates and updates in graph order":
    var calls: seq[uint32]
    proc record(component: DependencyComponent; dirt: ComponentDirt) =
      check dirt.containsAny(DirtTransform)
      calls.add(component.objectId)

    let root = newDependencyComponent(1, record, initialDirt = DirtNone)
    let child = newDependencyComponent(2, record, initialDirt = DirtNone)
    let leaf = newDependencyComponent(3, record, initialDirt = DirtNone)
    discard root.addDependent(child)
    discard child.addDependent(leaf)
    let solver = newDependencySolver()
    require solver.sortDependencies([root]).isOk

    check root.addDirt(DirtTransform, true)
    check not root.addDirt(DirtTransform, true)
    let updated = solver.updateComponents()
    require updated.isOk
    check updated.value
    check calls == @[1'u32, 2, 3]
    check solver.updateComponents().value == false

  test "dirtying an earlier component restarts the ordered pass":
    var calls: seq[uint32]
    var dirtiedEarlier = false
    let root = newDependencyComponent(1, initialDirt = DirtNone)
    let late = newDependencyComponent(2, initialDirt = DirtNone)
    root.updateHook = proc(component: DependencyComponent; dirt: ComponentDirt) =
      calls.add(component.objectId)
    late.updateHook = proc(component: DependencyComponent; dirt: ComponentDirt) =
      calls.add(component.objectId)
      if not dirtiedEarlier:
        dirtiedEarlier = true
        discard root.addDirt(DirtWorldTransform)
    discard root.addDependent(late)
    let solver = newDependencySolver()
    require solver.sortDependencies([root]).isOk
    discard root.addDirt(DirtTransform)
    discard late.addDirt(DirtTransform)

    let updated = solver.updateComponents()
    require updated.isOk
    check calls == @[1'u32, 2, 1]

  test "non-settling updates stop at the configured bound":
    let component = newDependencyComponent(9, initialDirt = DirtNone)
    component.updateHook = proc(current: DependencyComponent;
        dirt: ComponentDirt) =
      discard current.addDirt(DirtTransform)
    let solver = newDependencySolver(maxSteps = 3)
    require solver.sortDependencies([component]).isOk
    discard component.addDirt(DirtTransform)

    let result = solver.updateComponents()
    check not result.isOk
    check result.error.category == ErrorCategory.scene
    check result.error.stage == ErrorStage.frameAdvance
    check result.error.message == "dependency update did not settle"
