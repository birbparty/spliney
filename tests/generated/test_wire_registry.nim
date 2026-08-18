import std/unittest

import spliney/generated/wire_registry

proc artboardFactory(): GeneratedCoreObject = GeneratedCoreObject()

suite "generated wire registry":
  test "pins and covers the complete official defs registry":
    check OfficialRuntimeSha ==
      "372b8092e940f32cf84499ae23a4899ec66a9ab1"
    check DefsAggregateSha256 ==
      "69189bf0f5ef0ad4d3691048e2a351698cfd23494ff9d5b41ffc0e249d73f15f"
    check DefsFileCount == 353
    check TypeCount == 353
    check PropertyCount == 586

  test "keys are sorted and backing codes are complete":
    for index in 1 .. TypeRegistry.high:
      check TypeRegistry[index - 1].key < TypeRegistry[index].key
    for index in 1 .. PropertyRegistry.high:
      check PropertyRegistry[index - 1].key < PropertyRegistry[index].key
    for property in PropertyRegistry:
      check property.backingCode <= 3
      case property.wireKind
      of WireKind.uintValue: check property.backingCode == 0
      of WireKind.stringValue, WireKind.bytesValue:
        check property.backingCode == 1
      of WireKind.floatValue: check property.backingCode == 2
      of WireKind.colorValue: check property.backingCode == 3

  test "representative metadata preserves inheritance defaults and references":
    let artboard = typeMetadata(1)
    require not artboard.isNil
    check artboard.name == "Artboard"
    check artboard.parentKey == 409
    check artboard.mixins == @["publishable.json"]

    let originX = propertyMetadata(11)
    require not originX.isNil
    check originX.ownerTypeKey == 1
    check originX.wireKind == WireKind.floatValue
    check originX.initialValue == "0"

    let defaultStateMachine = propertyMetadata(236)
    require not defaultStateMachine.isNil
    check defaultStateMachine.isReference
    check defaultStateMachine.runtimeType == "uint"
    check defaultStateMachine.initialValueRuntime == "-1"

    let contents = propertyMetadata(212)
    require not contents.isNil
    check contents.ownerTypeKey == 106
    check contents.wireKind == WireKind.bytesValue
    check contents.backingCode == 1
    check typeMetadata(high(uint32)).isNil
    check propertyMetadata(high(uint32)).isNil

  test "factory skeleton rejects unknown and duplicate registrations":
    var factories: seq[tuple[key: uint32, factory: CoreFactoryProc]]
    factories.registerFactory(1, artboardFactory)
    let instance = factories.instantiate(1)
    require not instance.isNil
    check instance.typeKey == 1
    check factories.instantiate(2).isNil
    expect ValueError:
      factories.registerFactory(1, artboardFactory)
    expect ValueError:
      factories.registerFactory(high(uint32), artboardFactory)
