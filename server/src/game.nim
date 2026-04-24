import std/[tables, strformat]

import protocol

const
  BoardW = 10
  BoardH = 18
  CellSize = 12
  BoardX = 104
  BoardY = 18
  HudX = 8
  HudY = 18
  EmptyCell = 0'u8
  DirtyCell = 255'u8

  BackgroundColor = 0x101820'u32
  BoardColor = 0x0a1014'u32
  PanelColor = 0x1b2a33'u32
  TextColor = 0xffffff'u32
  BorderColor = 0x57c7ff'u32

  Palette = [
    0x000000'u32,
    0x57c7ff'u32,
    0xffbd2e'u32,
    0xb86bff'u32,
    0x28c840'u32,
    0xff5f57'u32,
    0x2f7bff'u32,
    0xff8f3d'u32
  ]

type
  Board = array[BoardH, array[BoardW, uint8]]

  PlayerState* = object
    playerId*: uint8
    board*: Board
    rendered*: Board
    activeKind*: uint8
    activeRot*: int
    activeX*: int
    activeY*: int
    dropTicks*: int
    spawnCount*: uint16
    score*: uint16
    lines*: uint16
    prevLeft*: bool
    prevRight*: bool
    prevRotate*: bool
    prevDrop*: bool
    needsFullRedraw*: bool
    renderedScore*: uint16
    renderedLines*: uint16
    clearToneTicks*: int

  GameState* = object
    arenaWidth*: int
    arenaHeight*: int
    players*: Table[uint8, PlayerState]

proc initRenderedBoard(): Board =
  for y in 0 ..< BoardH:
    for x in 0 ..< BoardW:
      result[y][x] = DirtyCell

proc initGame*(): GameState =
  result.arenaWidth = 320
  result.arenaHeight = 240
  result.players = initTable[uint8, PlayerState]()

proc blockOffset(kind: uint8, rot: int, index: int): tuple[x, y: int] =
  case kind
  of 0: # I
    if rot mod 2 == 0:
      case index
      of 0: (0, 1)
      of 1: (1, 1)
      of 2: (2, 1)
      else: (3, 1)
    else:
      case index
      of 0: (2, 0)
      of 1: (2, 1)
      of 2: (2, 2)
      else: (2, 3)
  of 1: # O
    case index
    of 0: (1, 0)
    of 1: (2, 0)
    of 2: (1, 1)
    else: (2, 1)
  of 2: # T
    case rot mod 4
    of 0:
      case index
      of 0: (1, 0)
      of 1: (0, 1)
      of 2: (1, 1)
      else: (2, 1)
    of 1:
      case index
      of 0: (1, 0)
      of 1: (1, 1)
      of 2: (2, 1)
      else: (1, 2)
    of 2:
      case index
      of 0: (0, 1)
      of 1: (1, 1)
      of 2: (2, 1)
      else: (1, 2)
    else:
      case index
      of 0: (1, 0)
      of 1: (0, 1)
      of 2: (1, 1)
      else: (1, 2)
  of 3: # S
    if rot mod 2 == 0:
      case index
      of 0: (1, 0)
      of 1: (2, 0)
      of 2: (0, 1)
      else: (1, 1)
    else:
      case index
      of 0: (1, 0)
      of 1: (1, 1)
      of 2: (2, 1)
      else: (2, 2)
  of 4: # Z
    if rot mod 2 == 0:
      case index
      of 0: (0, 0)
      of 1: (1, 0)
      of 2: (1, 1)
      else: (2, 1)
    else:
      case index
      of 0: (2, 0)
      of 1: (1, 1)
      of 2: (2, 1)
      else: (1, 2)
  of 5: # J
    case rot mod 4
    of 0:
      case index
      of 0: (0, 0)
      of 1: (0, 1)
      of 2: (1, 1)
      else: (2, 1)
    of 1:
      case index
      of 0: (1, 0)
      of 1: (2, 0)
      of 2: (1, 1)
      else: (1, 2)
    of 2:
      case index
      of 0: (0, 1)
      of 1: (1, 1)
      of 2: (2, 1)
      else: (2, 2)
    else:
      case index
      of 0: (1, 0)
      of 1: (1, 1)
      of 2: (0, 2)
      else: (1, 2)
  else: # L
    case rot mod 4
    of 0:
      case index
      of 0: (2, 0)
      of 1: (0, 1)
      of 2: (1, 1)
      else: (2, 1)
    of 1:
      case index
      of 0: (1, 0)
      of 1: (1, 1)
      of 2: (1, 2)
      else: (2, 2)
    of 2:
      case index
      of 0: (0, 1)
      of 1: (1, 1)
      of 2: (2, 1)
      else: (0, 2)
    else:
      case index
      of 0: (0, 0)
      of 1: (1, 0)
      of 2: (1, 1)
      else: (1, 2)

proc collides(player: PlayerState, testX, testY, testRot: int): bool =
  for i in 0 ..< 4:
    let pieceBlock = blockOffset(player.activeKind, testRot, i)
    let x = testX + pieceBlock.x
    let y = testY + pieceBlock.y
    if x < 0 or x >= BoardW or y >= BoardH:
      return true
    if y >= 0 and player.board[y][x] != EmptyCell:
      return true

proc spawnPiece(player: var PlayerState) =
  player.activeKind = uint8((int(player.spawnCount) + int(player.playerId) * 3) mod 7)
  player.activeRot = 0
  player.activeX = 3
  player.activeY = 0
  player.dropTicks = 0
  inc(player.spawnCount)

  if player.collides(player.activeX, player.activeY, player.activeRot):
    player.board = default(Board)
    player.rendered = initRenderedBoard()
    player.score = 0
    player.lines = 0
    player.renderedScore = high(uint16)
    player.renderedLines = high(uint16)

proc ensurePlayer(state: var GameState, playerId: uint8) =
  if state.players.hasKey(playerId):
    return

  var player = PlayerState(
    playerId: playerId,
    rendered: initRenderedBoard(),
    needsFullRedraw: true,
    renderedScore: high(uint16),
    renderedLines: high(uint16)
  )
  player.spawnPiece()
  state.players[playerId] = player

proc removePlayer*(state: var GameState, playerId: uint8) =
  if state.players.hasKey(playerId):
    state.players.del(playerId)

proc lockPiece(player: var PlayerState) =
  let color = player.activeKind + 1
  for i in 0 ..< 4:
    let pieceBlock = blockOffset(player.activeKind, player.activeRot, i)
    let x = player.activeX + pieceBlock.x
    let y = player.activeY + pieceBlock.y
    if x >= 0 and x < BoardW and y >= 0 and y < BoardH:
      player.board[y][x] = color

proc clearLines(player: var PlayerState) =
  var y = BoardH - 1
  var cleared = 0'u16
  while y >= 0:
    var full = true
    for x in 0 ..< BoardW:
      if player.board[y][x] == EmptyCell:
        full = false
        break

    if full:
      inc(cleared)
      for row in countdown(y, 1):
        player.board[row] = player.board[row - 1]
      player.board[0] = default(array[BoardW, uint8])
    else:
      dec(y)

  if cleared > 0:
    player.lines += cleared
    player.score += cleared * 100'u16
    player.clearToneTicks = 6

proc visibleCell(player: PlayerState, x, y: int): uint8 =
  result = player.board[y][x]
  for i in 0 ..< 4:
    let pieceBlock = blockOffset(player.activeKind, player.activeRot, i)
    if player.activeX + pieceBlock.x == x and player.activeY + pieceBlock.y == y:
      return player.activeKind + 1

proc updatePlayer(player: var PlayerState, input: InputSnapshot) =
  let left = input.joystickX < -12000
  let right = input.joystickX > 12000
  let down = input.joystickY > 12000
  let rotate = input.buttonA
  let drop = input.buttonB

  if left and not player.prevLeft and not player.collides(player.activeX - 1, player.activeY, player.activeRot):
    dec(player.activeX)
  if right and not player.prevRight and not player.collides(player.activeX + 1, player.activeY, player.activeRot):
    inc(player.activeX)
  if rotate and not player.prevRotate and not player.collides(player.activeX, player.activeY, player.activeRot + 1):
    player.activeRot = (player.activeRot + 1) mod 4
  if drop and not player.prevDrop:
    while not player.collides(player.activeX, player.activeY + 1, player.activeRot):
      inc(player.activeY)
    player.dropTicks = 999

  player.prevLeft = left
  player.prevRight = right
  player.prevRotate = rotate
  player.prevDrop = drop

  inc(player.dropTicks, if down: 4 else: 1)
  if player.dropTicks >= 18:
    player.dropTicks = 0
    if player.collides(player.activeX, player.activeY + 1, player.activeRot):
      player.lockPiece()
      player.clearLines()
      player.score += 5
      player.spawnPiece()
    else:
      inc(player.activeY)

  if player.clearToneTicks > 0:
    dec(player.clearToneTicks)

proc updateGame*(
  state: var GameState,
  inputs: Table[uint8, InputSnapshot],
  activePlayerIds: openArray[uint8]
) =
  for playerId in activePlayerIds:
    state.ensurePlayer(playerId)

  for playerId in activePlayerIds:
    var player = state.players[playerId]
    player.updatePlayer(inputs.getOrDefault(playerId, InputSnapshot()))
    state.players[playerId] = player

proc addRect(frame: var FrameState, x, y, w, h: int, color: uint32) =
  frame.drawCommands.add(DrawCommand(
    kind: dcFillRect,
    x: int16(x),
    y: int16(y),
    w: uint16(w),
    h: uint16(h),
    color: color
  ))

proc addText(frame: var FrameState, x, y: int, color: uint32, text: string) =
  frame.drawCommands.add(DrawCommand(
    kind: dcDrawText,
    x: int16(x),
    y: int16(y),
    color: color,
    text: text
  ))

proc addHud(frame: var FrameState, player: var PlayerState) =
  if player.needsFullRedraw or player.score != player.renderedScore or player.lines != player.renderedLines:
    frame.addRect(HudX, HudY, 86, 86, PanelColor)
    frame.addText(HudX + 6, HudY + 8, TextColor, "TETRIS")
    frame.addText(HudX + 6, HudY + 30, TextColor, &"SCORE {player.score}")
    frame.addText(HudX + 6, HudY + 52, TextColor, &"LINES {player.lines}")
    player.renderedScore = player.score
    player.renderedLines = player.lines

proc addBoardFrame(frame: var FrameState) =
  frame.addRect(0, 0, 320, 240, BackgroundColor)
  frame.addRect(BoardX - 3, BoardY - 3, BoardW * CellSize + 6, BoardH * CellSize + 6, BorderColor)
  frame.addRect(BoardX, BoardY, BoardW * CellSize, BoardH * CellSize, BoardColor)

proc buildFrameState*(state: var GameState, playerId: uint8, sequence: uint32): FrameState =
  state.ensurePlayer(playerId)
  var player = state.players[playerId]

  result.stateSequence = sequence
  result.outputs = OutputState(
    led1: if player.clearToneTicks > 0: 1 else: 0,
    led2: if playerId == 1: 1 else: 0,
    buzzerMode: if player.clearToneTicks > 0: 1 else: 0,
    buzzerFreqHz: 660,
    buzzerDuty: 12000
  )

  if player.needsFullRedraw:
    result.addBoardFrame()

  result.addHud(player)

  for y in 0 ..< BoardH:
    for x in 0 ..< BoardW:
      let cell = player.visibleCell(x, y)
      if player.needsFullRedraw or cell != player.rendered[y][x]:
        let color = if cell == EmptyCell: BoardColor else: Palette[cell]
        result.addRect(BoardX + x * CellSize, BoardY + y * CellSize, CellSize - 1, CellSize - 1, color)
        player.rendered[y][x] = cell

  player.needsFullRedraw = false
  state.players[playerId] = player
