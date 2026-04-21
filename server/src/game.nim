import std/[tables, strformat]

import protocol

type
  PlayerState* = object
    playerId*: uint8
    x*: float
    y*: float
    colorIndex*: int
    flashTicks*: int
    prevButtonB*: bool

  GameState* = object
    arenaWidth*: int
    arenaHeight*: int
    players*: Table[uint8, PlayerState]

const
  Palette = [
    0xff5f57'u32,
    0xffbd2e'u32,
    0x28c840'u32,
    0x57c7ff'u32,
    0xb86bff'u32,
    0xffffff'u32
  ]

proc clampFloat(value, minimum, maximum: float): float =
  if value < minimum:
    return minimum
  if value > maximum:
    return maximum
  value

proc initGame*(): GameState =
  result.arenaWidth = 320
  result.arenaHeight = 240
  result.players = initTable[uint8, PlayerState]()

proc ensurePlayer(state: var GameState, playerId: uint8) =
  if state.players.hasKey(playerId):
    return
  let idx = int(playerId)
  state.players[playerId] = PlayerState(
    playerId: playerId,
    x: 30.0 + float((idx - 1) * 60),
    y: 40.0 + float((idx - 1) * 40),
    colorIndex: (idx - 1) mod Palette.len,
    flashTicks: 0,
    prevButtonB: false
  )

proc removePlayer*(state: var GameState, playerId: uint8) =
  if state.players.hasKey(playerId):
    state.players.del(playerId)

proc updateGame*(
  state: var GameState,
  inputs: Table[uint8, InputSnapshot],
  activePlayerIds: openArray[uint8]
) =
  for playerId in activePlayerIds:
    state.ensurePlayer(playerId)

  for playerId in activePlayerIds:
    var player = state.players[playerId]
    let input = inputs.getOrDefault(playerId, InputSnapshot())
    let dx = float(input.joystickX) / 32767.0 * 4.0
    let dy = float(input.joystickY) / 32767.0 * 4.0
    player.x = clampFloat(player.x + dx, 0.0, float(state.arenaWidth - 18))
    player.y = clampFloat(player.y + dy, 18.0, float(state.arenaHeight - 18))

    if input.buttonA:
      player.flashTicks = 4
    elif player.flashTicks > 0:
      dec(player.flashTicks)

    if input.buttonB and not player.prevButtonB:
      player.colorIndex = (player.colorIndex + 1) mod Palette.len
    player.prevButtonB = input.buttonB
    state.players[playerId] = player

proc buildFrameState*(state: GameState, playerId: uint8, sequence: uint32): FrameState =
  result.stateSequence = sequence
  result.outputs = OutputState(
    led1: 0,
    led2: if playerId == 1: 1 else: 0,
    neopixelR: 0,
    neopixelG: 0,
    neopixelB: 32,
    buzzerMode: 0,
    buzzerFreqHz: 0,
    buzzerDuty: 0
  )

  result.drawCommands.add(DrawCommand(
    kind: dcFillRect,
    x: 0,
    y: 0,
    w: uint16(state.arenaWidth),
    h: uint16(state.arenaHeight),
    color: 0x101820'u32
  ))

  result.drawCommands.add(DrawCommand(
    kind: dcDrawText,
    x: 8,
    y: 8,
    color: 0xffffff'u32,
    text: &"PLAYER {playerId}"
  ))

  for currentId, player in state.players.pairs:
    let color = Palette[player.colorIndex]
    result.drawCommands.add(DrawCommand(
      kind: dcFillRect,
      x: int16(player.x),
      y: int16(player.y),
      w: 18'u16,
      h: 18'u16,
      color: if player.flashTicks > 0: 0xffffff'u32 else: color
    ))
    result.drawCommands.add(DrawCommand(
      kind: dcDrawText,
      x: int16(player.x),
      y: int16(player.y - 12.0),
      color: color,
      text: &"P{currentId}"
    ))

    if currentId == playerId and player.flashTicks > 0:
      result.outputs.led1 = 1
      result.outputs.neopixelR = 255
      result.outputs.neopixelG = 96
      result.outputs.neopixelB = 64
      result.outputs.buzzerMode = 1
      result.outputs.buzzerFreqHz = 880
      result.outputs.buzzerDuty = 18000
