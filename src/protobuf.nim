## This is a pure Nim implementation of protobuf, meaning that it doesn't rely
## on the ``protoc`` compiler. The entire implementation is based on a macro
## that takes in either a string or a file containing the proto3 format as
## specified at https://developers.google.com/protocol-buffers/docs/proto3. It
## then produces procedures to read, write, and calculate the length of a
## message, along with types to hold the data in your Nim program. The data
## types are intended to be as close as possible to what you would normally use
## in Nim, making it feel very natural to use these types in your program in
## contrast to some protobuf implementations. Protobuf 3 however has all fields
## as optional fields, this means that the types generated have a little bit of
## special sauce going on behind the scenes. This will be explained in a later
## section. The entire read/write structure is built on top of the Stream
## interface from the ``streams`` module, meaning it can be used directly with
## anything that uses streams.
##
## Example
## -------
## To whet your appetite the following example shows how this protobuf macro can
## be used to generate the required code and read and write protobuf messages.
## This example can also be found in the examples folder. Note that it is also
## possible to read in the protobuf specification from a file.
##
## .. code-block:: nim
##
##   import protobuf, streams
##
##   # Define our protobuf specification and generate Nim code to use it
##   const protoSpec = """
##   syntax = "proto3";
##
##   message ExampleMessage {
##     int32 number = 1;
##     string text = 2;
##     SubMessage nested = 3;
##     message SubMessage {
##       int32 a_field = 1;
##     }
##   }
##   """
##   parseProto(protoSpec)
##
##   # Create our message
##   var msg = new ExampleMessage
##   msg.number = 10
##   msg.text = "Hello world"
##   msg.nested = initExampleMessage_SubMessage(aField = 100)
##
##   # Write it to a stream
##   var stream = newStringStream()
##   stream.write msg
##
##   # Read the message from the stream and output the data, if it's all present
##   stream.setPosition(0)
##   var readMsg = stream.readExampleMessage()
##   if readMsg.has(number, text, nested) and readMsg.nested.has(aField):
##     echo readMsg.number
##     echo readMsg.text
##     echo readMsg.nested.aField
##
## Generated code
## --------------
## Since all the code is generated from the macro on compile-time and not stored
## anywhere the generated code is made to be deterministic and easy to
## understand. If you would like to see the code however you can pass
## ``-d:echoProtobuf`` switch on compile-time and the macro will output the
## generated code.
##
## Optional fields
## ^^^^^^^^^^^^^^^
## As mentioned earlier protobuf 3 makes all fields optional. This means that
## each field can either exist or not exist in a message. In many other protobuf
## implementations you notice this by having to use special getter or setter
## procs for field access. In Nim however we have strong meta-programming powers
## which can hide much of this complexity for us. As can be seen in the above
## example it looks just like normal Nim code except from one thing, the call to
## ``has``. Whenever a field is set to something it will register it's presence
## in the object. Then when you access the field Nim will first check if it is
## present or not, throwing a runtime ``ValueError`` if it isn't set. If you
## want to remove a value already set in an object you simply call ``reset``
## with the name of the field as seen in example 3. To check if a value exists
## or not you can call ``has`` on it as seen in the above example. Since it's a
## varargs call you can simply add all the fields you require in a single check.
## In the below sections we will have a look at what the protobuf macro outputs.
## Since the actual field names are hidden behind this abstraction the following
## sections will show what the objects "feel" like they are defined as. Notice
## also that since the fields don't actually have these names a regular object
## initialiser wouldn't work, therefore you have to use the "init" procs created
## as seen in the above example.
##
## Messages
## ^^^^^^^^
## The types generated are named after the path of the message, but with dots
## replaced by underscores. So if the protobuf specification contains a package
## name it starts with that, then the name of the message. If the message is
## nested then the parent message is put between the package and the message.
## As an example we can look at a protobuf message defined like this:
##
## .. code-block:: protobuf
##
##   syntax = "proto3"; // The only syntax supported
##   package = our.package;
##   message ExampleMessage {
##       int32 simpleField = 1;
##   }
##
## The type generated for this message would be named
## ``our_package_ExampleMessage``. Since Nim is case and underscore insensitive
## you can of course write this with any style you desire, be it camel-case,
## snake-case, or a mix as seen above. For this specific instance the type
## would appear to be:
##
## .. code-block:: nim
##
##   type
##     our_package_ExampleMessage = ref object
##       simpleField: int32
##
## Messages also generate a reader, writer, and length procedure to read,
## write, and get the length of a message on the wire respectively. All write
## procs are simply named ``write`` and are only differentiated by their types.
## This write procedure takes two arguments plus an optional third parameter,
## the ``Stream`` to write to, an instance of the message type to write, and a
## boolean telling it to prepend the message with a varint of it's length or
## not. This boolean is used for internal purposes, but might also come in handy
## if you want to stream multiple messages as described in
## https://developers.google.com/protocol-buffers/docs/techniques#streaming.
## The read procedure is named similarily to all the ``streams`` module
## readers, simply "read" appended with the name of the type. So for the above
## message the reader would be named ``read_our_package_ExampleMessage``.
## Notice again how you can write it in different styles in Nim if you'd like.
## One could of course also create an alias for this name should it prove too
## verbose. Analagously to the ``write`` procedure the reader also takes an
## optional ``maxSize`` argument of the maximum size to read for the message
## before returning. If the size is set to 0 the stream would be read until
## ``atEnd`` returns true. The ``len`` procedure is slightly simpler, it only
## takes an instance of the message type and returns the size this message would
## take on the wire, in bytes. This is used internally, but might have some
## other applications elsewhere as well. Notice that this size might vary from
## one instance of the type to another as varints can have multiple sizes,
## repeated fields different amount of elements, and oneofs having different
## choices to name a few.
##
## Enums
## ^^^^^
## Enums are named the same way as messages, and are always declared as pure.
## So an enum defined like this:
##
## .. code-block:: protobuf
##
##   syntax = "proto3"; // The only syntax supported
##   package = our.package;
##   enum Langs {
##     UNIVERSAL = 0;
##     NIM = 1;
##     C = 2;
##   }
##
## Would end up with a type like this:
##
## .. code-block:: nim
##
##   type
##     our_package_Langs {.pure.} = enum
##       UNIVERSAL = 0, NIM = 1, C = 2
##
## For internal use enums also generate a reader and writer procedure. These
## are basically a wrapper around the reader and writer for a varint, only that
## they convert to and from the enum type. Using these by themselves is seldom
## useful.
##
## OneOfs
## ^^^^^^
## In order for oneofs to work with Nims type system they generate their own
## type. This might change in the future. Oneofs are named the same way as
## their parent message, but with the name of the oneof field, and ``_OneOf``
## appended. All oneofs contain a field named ``option`` of a ranged integer
## from 0 to the number of options. This type is used to create an object
## variant for each of the fields in the oneof. So a oneof defined like this:
##
## .. code-block:: protobuf
##
##   syntax = "proto3"; // The only syntax supported
##   package our.package;
##   message ExampleMessage {
##     oneof choice {
##       int32 firstField = 1;
##       string secondField = 1;
##     }
##   }
##
## Will generate the following message and oneof type:
##
## .. code-block:: nim
##
##   type
##     our_package_ExampleMessage_choice_OneOf = object
##       case option: range[0 .. 1]
##       of 0: firstField: int32
##       of 1: secondField: string
##     our_package_ExampleMessage = ref object
##       choice: our_package_ExampleMessage_choice_OneOf
##
## Exporting message definitions
## -----------------------------
## If you want to re-use the same message definitions in multiple places in
## your code it's a good idea to create a module for you definition. This can
## also be useful if you want to rename some of the fields protobuf declares,
## or if you want to hide particular messages or create extra functionality.
## Since protobuf uses a little bit of magic under the hood a special
## `exportMessage` macro exists that will create the export statements you need
## in order to export a message definition from the module that reads the
## protobuf specification, to any module that imports it. Note however that it
## doesn't export sub-messages or any dependent types, so be sure to export
## those manually. Anything that's not a message (such as an enum) should be
## exported by the normal `export` statement.
##
## Limitations
## -----------
## This library is still in an early phase and has some limitations over the
## official version of protobuf. Noticably it only supports the "proto3"
## syntax, so no optional or required fields. It also doesn't currently support
## maps but you can use the official workaround found here:
## https://developers.google.com/protocol-buffers/docs/proto3#maps. This is
## planned to be added in the future. It also doesn't support options, meaning
## you can't set default values for enums and can't control packing options.
## That being said it follows the proto3 specification and will pack all scalar
## fields. It also doesn't support services.
##
## These limitations apply to the parser as well, so if you are using an
## existing protobuf specification you must remove these fields before being
## able to parse them with this library.
##
## If you find yourself in need of these features then I'd suggest heading over
## to https://github.com/oswjk/nimpb which uses the official protoc compiler
## with an extension to parse the protobuf file.
##
## Rationale
## ---------
## Some might be wondering why I've decided to create this library. After all
## the protobuf compiler is extensible and there are some other attempts at
## using protobuf within Nim by using this. The reason is three-fold, first off
## no-one likes to add an extra step to their compilation process. Running
## ``protoc`` before compiling isn't a big issue, but it's an extra
## compile-time dependency and it's more work. By using a regular Nim macro
## this is moved to a simple step in the compilation process. The only
## requirement is Nim and this library meaning tools can be automatically
## installed through nimble and still use protobuf. It also means that all of
## Nims targets are supported, and sending data between code compiled to C and
## Javascript should be a breeze and can share the exact same code for
## generating the messages. This is not yet tested, but any issues arising
## should be easy enough to fix. Secondly the programatic protobuf interface
## created for some languages are not the best. Python for example has some
## rather awkward and un-natural patterns for their protobuf library. By using
## a Nim macro the code can be customised to Nim much better and has the
## potential to create really native-feeling code resulting in a very nice
## interface. And finally this has been an interesting project in terms of
## pushing the macro system to do something most languages would simply be
## incapable of doing. It's not only a showcase of how much work the Nim
## compiler is able to do for you through its meta-programming, but has also
## been highly entertaining to work on.

import streams, strutils, sequtils, macros, tables
import protobuf/private/[parse, decldef, basetypes]
export basetypes
export macros
export strutils
export streams

type ValidationError = object of Defect

template ValidationAssert(statement: bool, error: string) =
  if not statement:
    raise newException(ValidationError, error)

proc getTypes(message: ProtoNode, parent = ""): seq[string] =
  result = @[]
  case message.kind:
    of ProtoDef:
      for package in message.packages:
        result = result.concat package.getTypes(parent)
    of Package:
      let name = (if parent != "": parent & "." else: "") & (if message.packageName == "": "" else: message.packageName)
      for definedEnum in message.packageEnums:
        ValidationAssert(definedEnum.kind == Enum, "Field for defined enums contained something else than a message")
        result.add name & "." & definedEnum.enumName
      for innerMessage in message.messages:
        result = result.concat innerMessage.getTypes(name)
    of Message:
      let name = (if parent != "": parent & "." else: "") & message.messageName
      for definedEnum in message.definedEnums:
        ValidationAssert(definedEnum.kind == Enum, "Field for defined enums contained something else than a message")
        result.add name & "." & definedEnum.enumName
      for innerMessage in message.nested:
        result = result.concat innerMessage.getTypes(name)
      result.add name
    else: ValidationAssert(false, "Unknown kind: " & $message.kind)

proc verifyAndExpandTypes(node: ProtoNode, validTypes: seq[string], parent: seq[string] = @[]) =
  case node.kind:
    of Field:
      block fieldBlock:
        #node.name = parent.join(".") & "." & node.name
        if node.protoType notin ["int32", "int64", "uint32", "uint64", "sint32", "sint64", "fixed32",
          "fixed64", "sfixed32", "sfixed64", "bool", "bytes", "enum", "float", "double", "string"]:
          if node.protoType[0] != '.':
            var depth = parent.len
            while depth > 0:
              if parent[0 ..< depth].join(".") & "." & node.protoType in validTypes:
                node.protoType = parent[0 ..< depth].join(".") & "." & node.protoType
                break fieldBlock
              depth -= 1
            if node.protoType in validTypes:
              break fieldBlock
          else:
            if node.protoType[1 .. ^1] in validTypes:
              node.protoType = node.protoType[1 .. ^1]
              break fieldBlock
            var depth = 0
            while depth < parent.len:
              if parent[depth .. ^1].join(".") & "." & node.protoType[1 .. ^1] in validTypes:
                node.protoType = parent[depth .. ^1].join(".") & "." & node.protoType[1 .. ^1]
                break fieldBlock
              depth += 1
          ValidationAssert(false, "Type not recognized: " & parent.join(".") & "." & node.protoType)
    of Enum:
      node.enumName = (if parent.len != 0: parent.join(".") & "." else: "") & node.enumName
    of Oneof:
      for field in node.oneof:
        verifyAndExpandTypes(field, validTypes, parent)
      node.oneofName = parent.join(".") & "." & node.oneofName
    of Message:
      var name = parent & node.messageName
      for field in node.fields:
        verifyAndExpandTypes(field, validTypes, name)
      for definedEnum in node.definedEnums:
        verifyAndExpandTypes(definedEnum, validTypes, name)
      for subMessage in node.nested:
        verifyAndExpandTypes(subMessage, validTypes, name)
      node.messageName = name.join(".")
    of ProtoDef:
      for node in node.packages:
        var name = parent.concat(if node.packageName == "": @[] else: node.packageName.split("."))
        for enu in node.packageEnums:
          verifyAndExpandTypes(enu, validTypes, name)
        for message in node.messages:
          verifyAndExpandTypes(message, validTypes, name)

    else: ValidationAssert(false, "Unknown kind: " & $node.kind)

proc verifyReservedAndUnique(message: ProtoNode) =
  ValidationAssert(message.kind == Message, "ProtoBuf messages field contains something else than messages")
  var
    usedNames: seq[string] = @[]
    usedIndices: seq[int] = @[]
  for field in message.fields:
    ValidationAssert(field.kind == Field or field.kind == Oneof, "Field for defined fields contained something else than a field")
    for field in (if field.kind == Field: @[field] else: field.oneof):
      ValidationAssert(field.name notin usedNames, "Field name already used")
      ValidationAssert(field.number notin usedIndices, "Field number already used")
      usedNames.add field.name
      usedIndices.add field.number
      for value in message.reserved:
        ValidationAssert(value.kind == Reserved, "Field for reserved values contained something else than a reserved value")
        case value.reservedKind:
          of String:
            ValidationAssert(value.strVal != field.name, "Field name in list of reserved names")
          of Number:
            ValidationAssert(value.intVal != field.number, "Field index in list of reserved indices")
          of Range:
            ValidationAssert(not(field.number >= value.startVal and field.number <= value.endVal), "Field index in list of reserved indices")
  for m in message.nested:
    verifyReservedAndUnique(m)

proc registerEnums(typeMapping: var Table[string, tuple[kind, write, read: NimNode, wire: int]], node: ProtoNode) =
  case node.kind:
  of Enum:
    typeMapping[node.enumName] = (kind: newIdentNode(node.enumName.replace(".", "_")), write: newIdentNode("write"), read: newIdentNode("read" & node.enumName.replace(".", "_")), wire: 0)
  of Message:
    for message in node.nested:
      registerEnums(typeMapping, message)
    for enu in node.definedEnums:
      registerEnums(typeMapping, enu)
  of ProtoDef:
    for node in node.packages:
      for message in node.messages:
        registerEnums(typeMapping, message)
      for enu in node.packageEnums:
        registerEnums(typeMapping, enu)
  else:
    discard

template getField*(obj: untyped, pos: int, field: untyped, name: string): untyped =
  if not obj.fields.contains(pos): raise newException(ValueError, "Field \"" & name & "\" isn't initialized")
  obj.field

proc findIgnoreStyle*(arr: openarray[string], field: string): int =
  for idx, fld in arr:
    if fld[0] == field[0]:
      if cmpIgnoreStyle(fld[0..^1], field[0..^1]) == 0:
        return idx
  return -1


{.experimental.}
template makeDot(kind, fieldArr: untyped): untyped =
  macro `.`(obj: kind, field: untyped): untyped =
    let
      fname = $field
      newField = newIdentNode("private_" & fname)
      idx = fieldArr.findIgnoreStyle(fname)
    assert idx != -1, "Couldn't find field \"" & fname & "\" in object"
    result = newTree(nnkStmtList,
      newTree(
        nnkCall,
        newTree(
          nnkDotExpr,
          obj,
          newIdentNode("getField")
        ),
        newLit(idx),
        newField,
        newLit(fname)
      )
    )

  macro `.=`(obj: kind, field: untyped, value: untyped): untyped =
    let
      fname = $field
      newField = newIdentNode("private_" & fname)
      idx = fieldArr.findIgnoreStyle(fname)
    assert idx != -1, "Couldn't find field \"" & fname & "\" in object"
    result = newTree(nnkStmtList,
      newTree(nnkCommand,
        newTree(nnkDotExpr,
          newTree(nnkDotExpr,
            obj,
            newIdentNode("fields")
          ),
          newIdentNode("incl")
        ),
        newLit(idx)
      ),
      newTree(nnkAsgn,
        newTree(nnkCall,
          newTree(nnkDotExpr,
            obj,
            newIdentNode("getField")
          ),
          newLit(idx),
          newField,
          newLit(fname)
        ),
        value
      )
    )

  macro has(obj: kind, fields: varargs[untyped]): untyped =
    result = newLit(true)
    for field in fields:
      let
        fname = $field
        idx = fieldArr.findIgnoreStyle(fname)
      assert idx != -1, "Couldn't find field \"" & fname & "\" in object"
      result = nnkInfix.newTree(
        newIdentNode("and"),
        nnkCall.newTree(
          newIdentNode("contains"),
          nnkDotExpr.newTree(
            obj,
            newIdentNode("fields")
          ),
          newLit(idx)
        ),
        result
      )

  macro reset(obj: kind, field: untyped): untyped =
    let
      fname = $field
      newField = newIdentNode("private_" & fname)
      idx = fieldArr.find(fname)
    assert idx != -1, "Couldn't find field in object"
    result = nnkStmtList.newTree(
      nnkCall.newTree(
        newIdentNode("excl"),
        nnkDotExpr.newTree(
          obj,
          newIdentNode("fields")
        ),
        newLit(idx)
      ),
      nnkCall.newTree(
        newIdentNode("reset"),
        nnkDotExpr.newTree(
          obj,
          newField
        )
      )
    )

proc genHelpers(typeName: NimNode, fieldNames: openarray[string]): NimNode {.compileTime.} =
  let
    macroName = newIdentNode("init" & $typeName)
    i = genSym(nskForVar)
    typeStr = $typeName
    res = newIdentNode("result")
    fieldsSym = genSym(nskVar)
    fieldsLen = fieldNames.len - 1
  var
    initialiserCases = quote do:
      case normalize($`i`[0]):
      else:
        discard
  var j = 0
  for field in fieldNames:
    let
      newFieldStr = "private_" & field
    initialiserCases.add((quote do:
      case 0:
      of normalize(`field`):
        `fieldsSym`.add nnkCall.newTree(
            nnkBracketExpr.newTree(
              newIdentNode("range"),
              nnkInfix.newTree(
                newIdentNode(".."),
                newLit(0),
                newLit(`fieldsLen`)
              )
            ),
            newLit(`j`)
          )
        `res`.add nnkExprColonExpr.newTree(
          newIdentNode(`newFieldStr`),
          `i`[1]
        )
    )[1])
    j += 1
  if fieldNames.len > 0:
    result = quote do:
      macro `macroName`(x: varargs[untyped]): untyped =
        `res` = nnkObjConstr.newTree(
          newIdentNode(`typeStr`)
        )
        var `fieldsSym` = newNimNode(nnkCurly)
        for `i` in x:
          `i`.expectKind(nnkExprEqExpr)
          `i`[0].expectKind(nnkIdent)
          `initialiserCases`
        `res`.add nnkExprColonExpr.newTree(
          newIdentNode("fields"),
          `fieldsSym`
        )
      makeDot(`typeName`, `fieldNames`)
  else:
    result = quote do:
      macro `macroName`(): untyped =
        `res` = nnkObjConstr.newTree(
          newIdentNode(`typeStr`)
        )

proc generateCode(typeMapping: Table[string, tuple[kind, write, read: NimNode, wire: int]], proto: ProtoNode): NimNode {.compileTime.} =
  var typeHelpers = newStmtList()
  proc generateTypes(node: ProtoNode, parent: var NimNode) =
    case node.kind:
    of Field:
      if node.repeated:
        parent.add(nnkIdentDefs.newTree(
          newIdentNode("private_" & node.name),
          nnkBracketExpr.newTree(
            newIdentNode("seq"),
            if typeMapping.hasKey(node.protoType): typeMapping[node.protoType].kind else: newIdentNode(node.protoType.replace(".", "_")),
          ),
          newEmptyNode()
        ))
      else:
        parent.add(nnkIdentDefs.newTree(
          newIdentNode("private_" & node.name),
          if typeMapping.hasKey(node.protoType): typeMapping[node.protoType].kind else: newIdentNode(node.protoType.replace(".", "_")),
          newEmptyNode()
        ))
    of EnumVal:
      parent.add(
        nnkEnumFieldDef.newTree(
          newIdentNode(node.fieldName),
          newIntLitNode(node.num)
        )
      )
    of Enum:
      var currentEnum = nnkTypeDef.newTree(
        nnkPragmaExpr.newTree(
          newIdentNode(node.enumName.replace(".", "_")),
          nnkPragma.newTree(newIdentNode("pure"))
        ),
        newEmptyNode()
      )
      var enumBlock = nnkEnumTy.newTree(newEmptyNode())
      for enumVal in node.values:
        generateTypes(enumVal, enumBlock)
      currentEnum.add(enumBlock)
      parent.add(currentEnum)
    of OneOf:
      var cases = nnkRecCase.newTree(
          nnkIdentDefs.newTree(
            newIdentNode("option"),
            nnkBracketExpr.newTree(
              newIdentNode("range"),
              nnkInfix.newTree(
                newIdentNode(".."),
                newLit(0),
                newLit(node.oneof.len - 1)
              )
            ),
            newEmptyNode()
          )
        )
      var curCase = 0
      for field in node.oneof:
        var caseBody = newNimNode(nnkRecList)
        if field.repeated:
          caseBody.add(nnkIdentDefs.newTree(
            newIdentNode(field.name),
            nnkBracketExpr.newTree(
              newIdentNode("seq"),
              if typeMapping.hasKey(field.protoType): typeMapping[field.protoType].kind else: newIdentNode(field.protoType.replace(".", "_")),
            ),
            newEmptyNode()
          ))
        else:
          caseBody.add(nnkIdentDefs.newTree(
            newIdentNode(field.name),
            if typeMapping.hasKey(field.protoType): typeMapping[field.protoType].kind else: newIdentNode(field.protoType.replace(".", "_")),
            newEmptyNode()
          ))
        cases.add(
          nnkOfBranch.newTree(
            newLit(curCase),
            caseBody
          )
        )
        curCase += 1
      parent.add(
        nnkTypeDef.newTree(
          newIdentNode(node.oneofName.replace(".", "_") & "_OneOf"),
          newEmptyNode(),
          nnkObjectTy.newTree(
            newEmptyNode(),
            newEmptyNode(),
            nnkRecList.newTree(
              cases
            )
          )
        )
      )
    of Message:
      var currentMessage = nnkTypeDef.newTree(
        newIdentNode(node.messageName.replace(".", "_")),
        newEmptyNode()
      )
      var messageBlock = nnkRecList.newNimNode()
      if node.fields.len > 0:
        messageBlock.add(nnkIdentDefs.newTree(
          newIdentNode("fields"),
          nnkBracketExpr.newTree(
            newIdentNode("set"),
            nnkBracketExpr.newTree(
              newIdentNode("range"),
              nnkInfix.newTree(
                newIdentNode(".."),
                newLit(0),
                newLit(node.fields.len - 1)
              )
            )
          ),
          newEmptyNode()
        ))
        var fields = newSeq[string](node.fields.len)
        for i, field in node.fields:
          if field.kind == Field:
            generateTypes(field, messageBlock)
            fields[i] = field.name.replace(".", "_")
          else:
            generateTypes(field, parent)
            let
              oneofType = field.oneofName.replace(".", "_") & "_OneOf"
              oneofName = field.oneofName.rsplit({'.'}, 1)[1]
            messageBlock.add(nnkIdentDefs.newTree(
              newIdentNode("private_" & oneofName),
              newIdentNode(oneofType),
              newEmptyNode()
            ))
            fields[i] = oneofName
        typeHelpers.add genHelpers(newIdentNode(node.messageName.replace(".", "_")), fields)
      else:
        typeHelpers.add genHelpers(newIdentNode(node.messageName.replace(".", "_")), @[])

      currentMessage.add(nnkRefTy.newTree(nnkObjectTy.newTree(newEmptyNode(), newEmptyNode(), messageBlock)))
      parent.add(currentMessage)
      for definedEnum in node.definedEnums:
        generateTypes(definedEnum, parent)
      for subMessage in node.nested:
        generateTypes(subMessage, parent)
    of ProtoDef:
      for node in node.packages:
        for message in node.messages:
          generateTypes(message, parent)
        for enu in node.packageEnums:
          generateTypes(enu, parent)
    else:
      echo "Unsupported kind: " & $node.kind
      discard
  proc generateFieldLen(typeMapping: Table[string, tuple[kind, write, read: NimNode, wire: int]], node: ProtoNode, field: NimNode): NimNode =
    result = newStmtList()
    let fieldDesc = newLit(getVarIntLen(node.number shl 3 or (if not node.repeated and typeMapping.hasKey(node.protoType): typeMapping[node.protoType].wire else: 2)))
    let res = newIdentNode("result")
    result.add(quote do:
      `res` += `fieldDesc`
    )
    if typeMapping.hasKey(node.protoType):
      case typeMapping[node.protoType].wire:
      of 1:
        if node.repeated:
          result.add(quote do:
            `res` += 8*`field`.len
          )
        else:
          result.add(quote do:
            `res` += 8
          )
      of 5:
        if node.repeated:
          result.add(quote do:
            `res` += 4*`field`.len
          )
        else:
          result.add(quote do:
            `res` += 4
          )
      of 2:
        if node.repeated:
          result.add(quote do:
            for i in `field`:
              `res` += i.len
              `res` += getVarIntLen(i.len.int64)
            `res` += `fieldDesc`*(`field`.len-1)
          )
        else:
          result.add(quote do:
            `res` += getVarIntLen(`field`.len.int64)
            `res` += `field`.len
          )
      of 0:
        let
          iVar = nskForVar.genSym()
          varInt = if node.repeated: nnkBracketExpr.newTree(field, iVar) else: field
          getVarIntLen = newIdentNode("getVarIntLen")
          innerBody = quote do:
            `res` += `getVarIntLen`(`varInt`)
          outerBody = if node.repeated: (quote do:
            for `iVar` in 0..`field`.high:
              `innerBody`
          ) else: innerBody
        result.add(outerBody)
      else:
        echo "Unable to create code"
        #raise newException(AssertionError, "Unable to generate code, wire type '" & $typeMapping[field.protoType].wire & "' not supported")
    else:
      if node.repeated:
        result.add(quote do:
          for i in `field`:
            let len = i.len
            `res` += len + getVarIntLen(len)
        )
      else:
        result.add(quote do:
          let len = `field`.len
          `res` += len + getVarIntLen(len)
        )

  proc generateFieldRead(typeMapping: Table[string, tuple[kind, write, read: NimNode, wire: int]], node: ProtoNode, stream, field: NimNode, parent: NimNode): NimNode =
    result = newStmtList()
    if node.repeated:
      if typeMapping.hasKey(node.protoType) and node.protoType != "string" and node.protoType != "bytes":
        let
          sizeSym = genSym(nskVar)
          protoRead = typeMapping[node.protoType].read
        result.add(quote do:
          var `sizeSym` = `stream`.protoReadInt64()
          `parent`.`field` = @[]
          let endPos = `stream`.getPosition() + `sizeSym`
          while `stream`.getPosition() < endPos:
            `parent`.`field`.add(`stream`.`protoRead`())
        )
      else:
        let
          protoRead = if typeMapping.hasKey(node.protoType): typeMapping[node.protoType].read else: newIdentNode("read" & node.protoType.replace(".", "_"))
          readStmt = if typeMapping.hasKey(node.protoType): quote do: `stream`.`protoRead`()
            else: quote do: `stream`.`protoRead`(`stream`.protoReadInt64()) #TODO: This is not implemented on the writer level
        result.add(quote do:
          if not `parent`.has(`field`):
            `parent`.`field` = @[]
          `parent`.`field`.add(`readStmt`)
        )
    else:
      let
        protoRead = if typeMapping.hasKey(node.protoType):
          typeMapping[node.protoType].read
        else:
          newIdentNode("read" & node.protoType.replace(".", "_"))
        readStmt = if typeMapping.hasKey(node.protoType):
          quote do: `stream`.`protoRead`()
        else:
          quote do:
            when compiles(`stream`.`protoRead`(`stream`.protoReadInt64())):
              `stream`.`protoRead`(`stream`.protoReadInt64())
            else:
              `stream`.`protoRead`()

      #result.add(quote do:
      #  `field` = `readStmt`
      #)
      result.add(nnkAsgn.newTree(nnkDotExpr.newTree(parent, field), readStmt))

  proc generateFieldWrite(typeMapping: Table[string, tuple[kind, write, read: NimNode, wire: int]], node: ProtoNode, stream, field: NimNode): NimNode =
    # Write field number and wire type
    result = newStmtList()
    let fieldWrite = nnkCall.newTree(
        newIdentNode("protoWriteInt64"),
        stream,
        newLit(node.number shl 3 or (if not node.repeated and typeMapping.hasKey(node.protoType): typeMapping[node.protoType].wire else: 2))
      )
    # If the field is repeated or has a repeated wire type, write it's length
    if typeMapping.hasKey(node.protoType) and node.protoType != "string" and node.protoType != "bytes":
      result.add(fieldWrite)
      if node.repeated:
        case typeMapping[node.protoType].wire:
        of 1:
          # Write 64bit * len
          result.add(quote do:
            `stream`.protoWriteInt64(8*`field`.len)
          )
        of 5:
          # Write 32bit * len
          result.add(quote do:
            `stream`.protoWriteInt64(4*`field`.len)
          )
        of 2:
          # Write len
          result.add(quote do:
            var bytes = 0
            for i in 0..`field`.high:
              bytes += `field`[i].len
            `stream`.protoWriteInt64(bytes)
          )
        of 0:
          # Sum varint lengths and write them
          result.add(quote do:
            var bytes = 0
            for i in 0..`field`.high:
              bytes += getVarIntLen(`field`[i])
            `stream`.protoWriteInt64(bytes)
          )
        else:
          echo "Unable to create code"
      let
        iVar = nskForVar.genSym()
        varInt = if node.repeated: nnkBracketExpr.newTree(field, iVar) else: field
        innerBody = nnkCall.newTree(
          typeMapping[node.protoType].write,
          stream,
          varInt
        )
        outerBody = if node.repeated: (quote do:
          for `iVar` in 0..`field`.high:
            `innerBody`
        ) else: innerBody
      result.add(outerBody)
    else:
      let
        iVar = nskForVar.genSym()
        varInt = if node.repeated: nnkBracketExpr.newTree(field, iVar) else: field
        protoWrite = if typeMapping.hasKey(node.protoType): typeMapping[node.protoType].write else: newEmptyNode()
        innerBody = if typeMapping.hasKey(node.protoType):
          quote do:
            `fieldWrite`
            `stream`.`protoWrite`(`varInt`)
        else:
          quote do:
            `fieldWrite`
            when compiles(`stream`.write(`varInt`, true)):
              `stream`.write(`varInt`, true)
            else:
              `stream`.write(`varInt`)
        outerBody = if node.repeated: (quote do:
          for `iVar` in 0..`field`.high:
            `innerBody`
        ) else: innerBody
      result.add(outerBody)

  proc generateProcs(typeMapping: Table[string, tuple[kind, write, read: NimNode, wire: int]], node: ProtoNode, decls: var NimNode, impls: var NimNode) =
    case node.kind:
      of Message:
        let
          readName = newIdentNode("read" & node.messageName.replace(".", "_"))
          messageType = newIdentNode(node.messageName.replace(".", "_"))
          res = newIdentNode("result")
          s = newIdentNode("s")
          o = newIdentNode("o")
          maxSize = newIdentNode("maxSize")
          writeSize = newIdentNode("writeSize")
        var procDecls = quote do:
          proc `readName`(`s`: Stream, `maxSize`: int64 = 0): `messageType`
          proc write(`s`: Stream, `o`: `messageType`, `writeSize` = false)
          proc len(`o`: `messageType`): int
        var procImpls = quote do:
          proc `readName`(`s`: Stream, `maxSize`: int64 = 0): `messageType` =
            `res` = new `messageType`
            let startPos = `s`.getPosition()
            while not `s`.atEnd and (`maxSize` == 0 or `s`.getPosition() < startPos + `maxSize`):
              let
                fieldSpec = `s`.protoReadInt64().uint64
                # wireType = fieldSpec and 0b111
                fieldNumber = fieldSpec shr 3
              case fieldNumber.int64:
          proc write(`s`: Stream, `o`: `messageType`, `writeSize` = false) =
            if `writeSize`:
              `s`.protoWriteInt64(`o`.len)
          proc len(`o`: `messageType`): int
        procImpls[2][6] = newStmtList()
        for field in node.fields:
          generateProcs(typeMapping, field, procDecls, procImpls)
        # TODO: Add generic reader for unknown types based on wire type
        procImpls[0][6][2][1][1].add(nnkElse.newTree(nnkStmtList.newTree(nnkDiscardStmt.newTree(newEmptyNode()))))
        for enumType in node.definedEnums:
          generateProcs(typeMapping, enumType, procDecls, procImpls)
        for message in node.nested:
          generateProcs(typeMapping, message, decls, impls)
        decls.add procDecls
        impls.add procImpls
      of OneOf:
        let
          oneofName = newIdentNode(node.oneofname.rsplit({'.'}, 1)[1])
          oneofType = newIdentNode(node.oneofname.replace(".", "_") & "_Oneof")
        for i in 0..node.oneof.high:
          let oneof = node.oneof[i]
          impls[0][6][2][1][1].add(nnkOfBranch.newTree(newLit(oneof.number),
            nnkStmtList.newTree(
              nnkAsgn.newTree(nnkDotExpr.newTree(newIdentNode("result"), oneofName),
                quote do: `oneofType`(option: `i`)
              ),
              generateFieldRead(typeMapping, oneof, impls[1][3][1][0], newIdentNode(oneof.name), nnkDotExpr.newTree(newIdentNode("result"), oneofName))
            )
          ))
        var
          oneofWriteBlock = nnkCaseStmt.newTree(
              nnkDotExpr.newTree(nnkDotExpr.newTree(impls[1][3][2][0], oneofName), newIdentNode("option"))
            )
          oneofLenBlock = nnkCaseStmt.newTree(
              nnkDotExpr.newTree(nnkDotExpr.newTree(impls[2][3][1][0], oneofName), newIdentNode("option"))
            )

        let parent = impls[1][3][2][0]
        for i in 0..node.oneof.high:
          oneofWriteBlock.add(nnkOfBranch.newTree(
              newLit(i),
              generateFieldWrite(typeMapping, node.oneof[i], impls[1][3][1][0],
                nnkDotExpr.newTree(nnkDotExpr.newTree(parent, oneofName), newIdentNode(node.oneof[i].name))
              )
            )
          )
        impls[1][6].add(quote do:
          if `parent`.has(`oneofName`):
            `oneofWriteBlock`
        )
        let lenParent = impls[2][3][1][0]
        for i in 0..node.oneof.high:
          oneofLenBlock.add(nnkOfBranch.newTree(
              newLit(i),
              generateFieldLen(typeMapping, node.oneof[i],
                nnkDotExpr.newTree(nnkDotExpr.newTree(lenParent, oneofName), newIdentNode(node.oneof[i].name))
              )
            )
          )
        impls[2][6].add(quote do:
          if `lenParent`.has(`oneofName`):
            `oneofLenBlock`
        )
      of Field:
        impls[0][6][2][1][1].add(nnkOfBranch.newTree(newLit(node.number),
          generateFieldRead(typeMapping, node, impls[0][3][1][0], newIdentNode(node.name), newIdentNode("result"))
        ))
        let
          field = newIdentNode(node.name)
          parent = impls[1][3][2][0]
          lenParent = impls[2][3][1][0]
          fieldWrite = generateFieldWrite(typeMapping, node, impls[1][3][1][0], nnkDotExpr.newTree(parent, field))
          fieldLen = generateFieldLen(typeMapping, node, nnkDotExpr.newTree(lenParent, field))
        impls[1][6].add(quote do:
          if `parent`.has(`field`):
            `fieldWrite`
        )
        impls[2][6].add(quote do:
          if `lenParent`.has(`field`):
            `fieldLen`
        )
      of Enum:
        let
          readName = newIdentNode("read" & node.enumName.replace(".", "_"))
          enumType = newIdentNode(node.enumName.replace(".", "_"))
          s = newIdentNode("s")
          o = newIdentNode("o")
          e = newIdentNode("e")
        decls.add quote do:
          proc `readName`(`s`: Stream): `enumType`
          proc write(`s`: Stream, `o`: `enumType`)
          proc getVarIntLen(`e`: `enumType`): int
        impls.add quote do:
          proc `readName`(`s`: Stream): `enumType` =
              `s`.protoReadInt64().`enumType`
          proc write(`s`: Stream, `o`: `enumType`) =
            `s`.protoWriteInt64(`o`.int64)
          proc getVarIntLen(`e`: `enumType`): int =
            getVarIntLen(`e`.int64)
      of ProtoDef:
        for node in node.packages:
          for message in node.messages:
            generateProcs(typeMapping, message, decls, impls)
          for packageEnum in node.packageEnums:
            generateProcs(typeMapping, packageEnum, decls, impls)
      else:
        echo "Unsupported kind: " & $node.kind
        discard

  var
    typeBlock = nnkTypeSection.newTree()
    forwardDeclarations = newStmtList()
    implementations = newStmtList()
  proto.generateTypes(typeBlock)
  generateProcs(typeMapping, proto, forwardDeclarations, implementations)
  result = quote do:
    {.experimental.}
    `typeBlock`
    `typeHelpers`
    `forwardDeclarations`
    `implementations`

proc parseImpl(protoParsed: ProtoNode): NimNode {.compileTime.} =
  var validTypes = protoParsed.getTypes()
  protoParsed.verifyAndExpandTypes(validTypes)

  var typeMapping = {
    "int32": (kind: newIdentNode("int32"), write: newIdentNode("protoWriteint32"), read: newIdentNode("protoReadint32"), wire: 0),
    "int64": (kind: newIdentNode("int64"), write: newIdentNode("protoWriteint64"), read: newIdentNode("protoReadint64"), wire: 0),
    "uint32": (kind: newIdentNode("uint32"), write: newIdentNode("protoWriteuint32"), read: newIdentNode("protoReaduint32"), wire: 0),
    "uint64": (kind: newIdentNode("uint64"), write: newIdentNode("protoWriteuint64"), read: newIdentNode("protoReaduint64"), wire: 0),
    "sint32": (kind: newIdentNode("int32"), write: newIdentNode("protoWritesint32"), read: newIdentNode("protoReadsint32"), wire: 0),
    "sint64": (kind: newIdentNode("int64"), write: newIdentNode("protoWritesint64"), read: newIdentNode("protoReadsint64"), wire: 0),
    "fixed32": (kind: newIdentNode("uint32"), write: newIdentNode("protoWritefixed32"), read: newIdentNode("protoReadfixed32"), wire: 5),
    "fixed64": (kind: newIdentNode("uint64"), write: newIdentNode("protoWritefixed64"), read: newIdentNode("protoReadfixed64"), wire: 1),
    "sfixed32": (kind: newIdentNode("int32"), write: newIdentNode("protoWritesfixed32"), read: newIdentNode("protoReadsfixed32"), wire: 5),
    "sfixed64": (kind: newIdentNode("int64"), write: newIdentNode("protoWritesfixed64"), read: newIdentNode("protoReadsfixed64"), wire: 1),
    "bool": (kind: newIdentNode("bool"), write: newIdentNode("protoWritebool"), read: newIdentNode("protoReadbool"), wire: 0),
    "float": (kind: newIdentNode("float32"), write: newIdentNode("protoWritefloat"), read: newIdentNode("protoReadfloat"), wire: 5),
    "double": (kind: newIdentNode("float64"), write: newIdentNode("protoWritedouble"), read: newIdentNode("protoReaddouble"), wire: 1),
    "string": (kind: newIdentNode("string"), write: newIdentNode("protoWritestring"), read: newIdentNode("protoReadstring"), wire: 2),
    "bytes": (kind: parseExpr("seq[uint8]"), write: newIdentNode("protoWritebytes"), read: newIdentNode("protoReadbytes"), wire: 2)
  }.toTable

  typeMapping.registerEnums(protoParsed)
  result = generateCode(typeMapping, protoParsed)
  when defined(echoProtobuf):
    echo result.toStrLit

macro exportMessage*(typename: untyped): untyped =
  ## Creates export statements required to use a type. Useful if you want to
  ## make a module for you protobuf specification.
  result = newStmtList()
  result.add nnkExportStmt.newTree typename
  result.add nnkExportStmt.newTree newIdentNode("init" & $typename)
  result.add nnkExportStmt.newTree newIdentNode("read" & $typename)
  result.add nnkExportStmt.newTree newIdentNode("write")
  result.add nnkExportStmt.newTree newIdentNode("has")
  result.add nnkExportStmt.newTree newIdentNode(".")
  result.add nnkExportStmt.newTree newIdentNode(".=")
  result.add nnkExportStmt.newTree newIdentNode("getField")

macro parseProto*(spec: static[string]): untyped =
  ## Parses the protobuf specification contained in the ``spec`` argument. This
  ## generates the code to use the messages specified within. See the
  ## introduction to this documentation for how this code is generated. NOTE:
  ## Currently the implementation will always use ``readFile`` to get the
  ## specification for any imported files. This will change in the future.
  parseImpl(parseToDefinition(spec))

macro parseProtoFile*(file: static[string]): untyped =
  ## Parses the protobuf specification contained in the file found at the path
  ## argument ``file``. This generates the code to use the messages specified
  ## within. See the introduction to this documentation for how this code is
  ## generated.
  var protoStr = readFile(file).string
  parseImpl(parseToDefinition(protoStr))
