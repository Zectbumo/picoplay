import std/os

import protocol

type
  ServerConfig* = object
    protocolVersion*: uint16
    gameVersion*: uint16
    tickHz*: uint16
    port*: uint16
    beaconPort*: uint16
    beaconIntervalMs*: int
    playerGraceMs*: int
    serverName*: string
    gameTitle*: string
    serverUuidPath*: string
    assetDir*: string

proc defaultConfig*(): ServerConfig =
  result.protocolVersion = 1
  result.gameVersion = 1
  result.tickHz = 30
  result.port = 41010
  result.beaconPort = 37020
  result.beaconIntervalMs = 1000
  result.playerGraceMs = 5000
  result.serverName = "picoplay"
  result.gameTitle = "picoplay sample"
  result.serverUuidPath = "server/server_uuid.txt"
  result.assetDir = "server/assets"

proc loadOrCreateServerUuid*(path: string): UuidBytes =
  if fileExists(path):
    return hexToUuid(readFile(path))

  let parentDir = splitFile(path).dir
  if parentDir.len > 0:
    createDir(parentDir)
  result = randomUuid()
  writeFile(path, uuidToHex(result))
