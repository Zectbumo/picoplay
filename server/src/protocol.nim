import std/[asyncdispatch, asyncnet, strutils, random]

type
  UuidBytes* = array[16, byte]

  AssetEntry* = object
    assetId*: uint16
    assetType*: uint8
    modTime*: uint64
    sizeBytes*: uint32
    path*: string

  InputSnapshot* = object
    joystickX*: int16
    joystickY*: int16
    buttonA*: bool
    buttonB*: bool

  DrawCommandKind* = enum
    dcDrawImage = 1'u8,
    dcDrawAtlas = 2'u8,
    dcFillRect = 3'u8,
    dcDrawText = 4'u8

  DrawCommand* = object
    kind*: DrawCommandKind
    assetId*: uint16
    atlasIndex*: uint16
    x*: int16
    y*: int16
    w*: uint16
    h*: uint16
    color*: uint32
    text*: string

  OutputState* = object
    led1*: uint8
    led2*: uint8
    neopixelR*: uint8
    neopixelG*: uint8
    neopixelB*: uint8
    buzzerMode*: uint8
    buzzerFreqHz*: uint16
    buzzerDuty*: uint16

  FrameState* = object
    stateSequence*: uint32
    drawCommands*: seq[DrawCommand]
    outputs*: OutputState

const
  PacketClientHello* = 1'u8
  PacketInputSnapshot* = 2'u8
  PacketServerHello* = 100'u8
  PacketAssetManifest* = 101'u8
  PacketAssetData* = 102'u8

  MagicBytes* = [byte('P'), byte('P'), byte('L'), byte('Y')]

proc randomUuid*(): UuidBytes =
  for index in 0 ..< result.len:
    result[index] = byte(rand(255))

proc uuidToHex*(uuid: UuidBytes): string =
  result = newStringOfCap(32)
  for value in uuid:
    result.add(toHex(value, 2))

proc hexToUuid*(value: string): UuidBytes =
  let compact = value.strip()
  if compact.len != 32:
    return
  for index in 0 ..< result.len:
    let offset = index * 2
    result[index] = byte(parseHexInt(compact[offset .. offset + 1]))

proc appendU8(buffer: var string, value: uint8) =
  buffer.add(char(value))

proc appendU16(buffer: var string, value: uint16) =
  buffer.add(char((value shr 8) and 0xff))
  buffer.add(char(value and 0xff))

proc appendI16(buffer: var string, value: int16) =
  buffer.appendU16(cast[uint16](value))

proc appendU32(buffer: var string, value: uint32) =
  buffer.add(char((value shr 24) and 0xff))
  buffer.add(char((value shr 16) and 0xff))
  buffer.add(char((value shr 8) and 0xff))
  buffer.add(char(value and 0xff))

proc appendU64(buffer: var string, value: uint64) =
  for shift in countdown(56, 0, 8):
    buffer.add(char((value shr shift) and 0xff'u64))

proc appendBytes(buffer: var string, value: UuidBytes) =
  for item in value:
    buffer.add(char(item))

proc appendString(buffer: var string, value: string) =
  buffer.appendU16(uint16(value.len))
  buffer.add(value)

proc readU8*(payload: string, offset: var int): uint8 =
  result = uint8(ord(payload[offset]))
  inc(offset)

proc readBool*(payload: string, offset: var int): bool =
  result = readU8(payload, offset) != 0

proc readU16*(payload: string, offset: var int): uint16 =
  result = (uint16(ord(payload[offset])) shl 8) or uint16(ord(payload[offset + 1]))
  inc(offset, 2)

proc readI16*(payload: string, offset: var int): int16 =
  result = cast[int16](readU16(payload, offset))

proc readU32*(payload: string, offset: var int): uint32 =
  result =
    (uint32(ord(payload[offset])) shl 24) or
    (uint32(ord(payload[offset + 1])) shl 16) or
    (uint32(ord(payload[offset + 2])) shl 8) or
    uint32(ord(payload[offset + 3]))
  inc(offset, 4)

proc readU64*(payload: string, offset: var int): uint64 =
  result = 0
  for _ in 0 ..< 8:
    result = (result shl 8) or uint64(ord(payload[offset]))
    inc(offset)

proc readUuid*(payload: string, offset: var int): UuidBytes =
  for index in 0 ..< result.len:
    result[index] = byte(ord(payload[offset + index]))
  inc(offset, result.len)

proc readString*(payload: string, offset: var int): string =
  let length = int(readU16(payload, offset))
  result = payload[offset ..< offset + length]
  inc(offset, length)

proc recvExact*(socket: AsyncSocket, size: int): Future[string] {.async.} =
  result = newStringOfCap(size)
  while result.len < size:
    let chunk = await socket.recv(size - result.len)
    if chunk.len == 0:
      raise newException(IOError, "socket closed while reading")
    result.add(chunk)

proc readPacket*(socket: AsyncSocket): Future[tuple[packetType: uint8, payload: string]] {.async.} =
  let header = await recvExact(socket, 3)
  var offset = 0
  result.packetType = readU8(header, offset)
  let payloadLength = int(readU16(header, offset))
  result.payload = await recvExact(socket, payloadLength)

proc sendPacket*(socket: AsyncSocket, packetType: uint8, payload: string) {.async.} =
  var frame = newStringOfCap(payload.len + 3)
  frame.appendU8(packetType)
  frame.appendU16(uint16(payload.len))
  frame.add(payload)
  await socket.send(frame)

proc encodeBeacon*(
  protocolVersion: uint16,
  serverUuid: UuidBytes,
  sessionUuid: UuidBytes,
  port: uint16,
  serverName: string
): string =
  result = newStringOfCap(64 + serverName.len)
  for item in MagicBytes:
    result.add(char(item))
  result.appendU16(protocolVersion)
  result.appendBytes(serverUuid)
  result.appendBytes(sessionUuid)
  result.appendU16(port)
  result.appendString(serverName)

proc decodeClientHello*(payload: string): tuple[hasUuid: bool, clientUuid: UuidBytes] =
  var offset = 0
  result.hasUuid = readBool(payload, offset)
  if result.hasUuid:
    result.clientUuid = readUuid(payload, offset)

proc decodeInputSnapshot*(payload: string): InputSnapshot =
  var offset = 0
  result.joystickX = readI16(payload, offset)
  result.joystickY = readI16(payload, offset)
  result.buttonA = readBool(payload, offset)
  result.buttonB = readBool(payload, offset)

proc encodeServerHello*(
  clientUuid: UuidBytes,
  sessionUuid: UuidBytes,
  gameVersion: uint16,
  gameTitle: string,
  tickHz: uint16,
  playerId: uint8
): string =
  result = newStringOfCap(64 + gameTitle.len)
  result.appendBytes(clientUuid)
  result.appendBytes(sessionUuid)
  result.appendU16(gameVersion)
  result.appendString(gameTitle)
  result.appendU16(tickHz)
  result.appendU8(playerId)

proc encodeAssetManifest*(entries: openArray[AssetEntry]): string =
  result = newStringOfCap(2 + entries.len * 15)
  result.appendU16(uint16(entries.len))
  for entry in entries:
    result.appendU16(entry.assetId)
    result.appendU8(entry.assetType)
    result.appendU64(entry.modTime)
    result.appendU32(entry.sizeBytes)

proc encodeAssetData*(entry: AssetEntry, payload: string): string =
  result = newStringOfCap(14 + payload.len)
  result.appendU16(entry.assetId)
  result.appendU64(entry.modTime)
  result.appendU32(entry.sizeBytes)
  result.add(payload)

proc encodeFrameState*(frame: FrameState): string =
  result = newStringOfCap(64 + frame.drawCommands.len * 16)
  result.appendU32(frame.stateSequence)
  result.appendU16(uint16(frame.drawCommands.len))
  for command in frame.drawCommands:
    result.appendU8(uint8(command.kind))
    case command.kind
    of dcDrawImage:
      result.appendU16(command.assetId)
      result.appendI16(command.x)
      result.appendI16(command.y)
    of dcDrawAtlas:
      result.appendU16(command.assetId)
      result.appendU16(command.atlasIndex)
      result.appendI16(command.x)
      result.appendI16(command.y)
    of dcFillRect:
      result.appendI16(command.x)
      result.appendI16(command.y)
      result.appendU16(command.w)
      result.appendU16(command.h)
      result.appendU32(command.color)
    of dcDrawText:
      result.appendI16(command.x)
      result.appendI16(command.y)
      result.appendU32(command.color)
      result.appendString(command.text)
  result.appendU8(frame.outputs.led1)
  result.appendU8(frame.outputs.led2)
  result.appendU8(frame.outputs.neopixelR)
  result.appendU8(frame.outputs.neopixelG)
  result.appendU8(frame.outputs.neopixelB)
  result.appendU8(frame.outputs.buzzerMode)
  result.appendU16(frame.outputs.buzzerFreqHz)
  result.appendU16(frame.outputs.buzzerDuty)
