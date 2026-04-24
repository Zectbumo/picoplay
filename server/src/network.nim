import std/[asyncdispatch, asyncnet, net, tables, times, sets, strformat]

import config, protocol, assets, game, beacon

type
  ClientConnection = ref object
    socket: AsyncSocket
    uuid: UuidBytes
    uuidKey: string
    remoteAddress: string
    clientUdpPort: uint16
    udpRegistered: bool
    playerId: uint8
    latestInput: InputSnapshot
    connected: bool
    reservedUntilMs: int64

  Server* = ref object
    cfg*: ServerConfig
    serverUuid*: UuidBytes
    sessionUuid*: UuidBytes
    tcpSocket*: AsyncSocket
    udpSocket*: AsyncSocket
    beaconSocket*: AsyncSocket
    assetStore*: AssetStore
    gameState*: GameState
    stateSequence*: uint32
    clients*: Table[string, ClientConnection]

proc nowMs(): int64 =
  int64(epochTime() * 1000)

proc activeClients(server: Server): seq[ClientConnection] =
  for client in server.clients.values:
    if client.connected:
      result.add(client)

proc expireReservations(server: Server) =
  let current = nowMs()
  for key, client in server.clients.mpairs:
    if not client.connected and client.playerId != 0 and client.reservedUntilMs <= current:
      server.gameState.removePlayer(client.playerId)
      client.playerId = 0

proc choosePlayerId(server: Server, uuidKey: string): uint8 =
  let current = nowMs()
  if server.clients.hasKey(uuidKey):
    let existing = server.clients[uuidKey]
    if existing.playerId != 0 and (existing.connected or existing.reservedUntilMs > current):
      return existing.playerId

  var used = initHashSet[uint8]()
  for client in server.clients.values:
    if client.playerId != 0 and (client.connected or client.reservedUntilMs > current):
      used.incl(client.playerId)

  for candidate in 1'u8 .. 4'u8:
    if candidate notin used:
      return candidate
  0'u8

proc syncAssets(server: Server, client: ClientConnection) {.async.} =
  await sendPacket(client.socket, PacketAssetManifest, encodeAssetManifest(server.assetStore.manifest))
  for entry in server.assetStore.manifest:
    let payload = server.assetStore.readAssetPayload(entry)
    await sendPacket(client.socket, PacketAssetData, encodeAssetData(entry, payload))

proc attachClient(
  server: Server,
  socket: AsyncSocket,
  remoteAddress: string,
  hello: tuple[hasUuid: bool, clientUuid: UuidBytes]
): ClientConnection =
  let assignedUuid = if hello.hasUuid: hello.clientUuid else: randomUuid()
  let uuidKey = uuidToHex(assignedUuid)
  let assignedPlayer = choosePlayerId(server, uuidKey)

  if server.clients.hasKey(uuidKey):
    result = server.clients[uuidKey]
  else:
    result = ClientConnection(uuid: assignedUuid, uuidKey: uuidKey)
    server.clients[uuidKey] = result

  result.socket = socket
  result.remoteAddress = remoteAddress
  result.clientUdpPort = 0
  result.udpRegistered = false
  result.playerId = assignedPlayer
  result.connected = true
  result.reservedUntilMs = 0
  result.latestInput = InputSnapshot()

proc markDisconnected(client: ClientConnection, graceMs: int) =
  client.connected = false
  client.reservedUntilMs = nowMs() + int64(graceMs)

proc handleClient(server: Server, socket: AsyncSocket) {.async.} =
  var attached: ClientConnection = nil
  try:
    let remoteAddress = socket.getPeerAddr()[0]
    let firstPacket = await readPacket(socket)
    if firstPacket.packetType != PacketClientHello:
      raise newException(IOError, "expected ClientHello")

    let hello = decodeClientHello(firstPacket.payload)
    attached = server.attachClient(socket, remoteAddress, hello)

    let helloPayload = encodeServerHello(
      attached.uuid,
      server.sessionUuid,
      server.cfg.gameVersion,
      server.cfg.gameTitle,
      server.cfg.tickHz,
      attached.playerId
    )
    await sendPacket(socket, PacketServerHello, helloPayload)
    await server.syncAssets(attached)

    while true:
      let packet = await readPacket(socket)
      if packet.packetType == PacketInputSnapshot:
        attached.latestInput = decodeInputSnapshot(packet.payload)
  except CatchableError:
    discard
  finally:
    if attached != nil:
      attached.markDisconnected(server.cfg.playerGraceMs)
    try:
      socket.close()
    except CatchableError:
      discard

proc acceptLoop(server: Server) {.async.} =
  while true:
    let client = await server.tcpSocket.accept()
    asyncCheck server.handleClient(client)

proc beaconLoop(server: Server) {.async.} =
  let payload = buildBeaconPayload(server.cfg, server.serverUuid, server.sessionUuid)
  while true:
    await server.beaconSocket.sendTo("255.255.255.255", Port(server.cfg.beaconPort), payload)
    await sleepAsync(server.cfg.beaconIntervalMs)

proc udpRegisterLoop(server: Server) {.async.} =
  while true:
    let packet = await server.udpSocket.recvFrom(1024)
    if packet.data.len != 16:
      continue

    var offset = 0
    let uuidKey = uuidToHex(readUuid(packet.data, offset))
    if server.clients.hasKey(uuidKey):
      server.clients[uuidKey].remoteAddress = packet.address
      server.clients[uuidKey].clientUdpPort = uint16(packet.port)
      server.clients[uuidKey].udpRegistered = true

proc gameLoop(server: Server) {.async.} =
  let tickDelay = max(1, int(1000 div server.cfg.tickHz))
  while true:
    server.expireReservations()

    var inputs = initTable[uint8, InputSnapshot]()
    var playerIds: seq[uint8] = @[]
    for client in server.activeClients():
      if client.playerId == 0 or not client.udpRegistered:
        continue
      playerIds.add(client.playerId)
      inputs[client.playerId] = client.latestInput

    server.gameState.updateGame(inputs, playerIds)
    inc(server.stateSequence)

    for client in server.activeClients():
      if client.playerId == 0 or not client.udpRegistered:
        continue
      let frame = server.gameState.buildFrameState(client.playerId, server.stateSequence)
      let payload = encodeFrameState(frame)
      await server.udpSocket.sendTo(client.remoteAddress, Port(client.clientUdpPort), payload)

    await sleepAsync(tickDelay)

proc runServer*(cfg: ServerConfig) =
  let server = Server(
    cfg: cfg,
    serverUuid: loadOrCreateServerUuid(cfg.serverUuidPath),
    sessionUuid: randomUuid(),
    assetStore: loadAssets(cfg.assetDir),
    gameState: initGame(),
    clients: initTable[string, ClientConnection]()
  )

  server.tcpSocket = newAsyncSocket()
  server.tcpSocket.setSockOpt(OptReuseAddr, true)
  server.tcpSocket.bindAddr(Port(cfg.port))
  server.tcpSocket.listen()

  server.udpSocket = newAsyncSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
  server.udpSocket.setSockOpt(OptReuseAddr, true)
  server.udpSocket.bindAddr(Port(cfg.port))

  server.beaconSocket = newAsyncSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
  server.beaconSocket.setSockOpt(OptReuseAddr, true)
  server.beaconSocket.setSockOpt(OptBroadcast, true)

  echo &"picoplay server listening on port={cfg.port} beacon={cfg.beaconPort}"
  echo &"session={uuidToHex(server.sessionUuid)} assets={server.assetStore.manifest.len}"

  asyncCheck server.acceptLoop()
  asyncCheck server.beaconLoop()
  asyncCheck server.udpRegisterLoop()
  asyncCheck server.gameLoop()
  runForever()
