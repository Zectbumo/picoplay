import std/[net, strformat, strutils, times, osproc, parseopt, os]

const
  UtilityVersion = "1.0.0"
  DefaultBeaconPort = 37020
  ExpectedProtocolVersion = 1'u16
  ExpectedMagic = "PPLY"
  MaxPacketBytes = 2048

type
  UuidBytes = array[16, byte]

  BeaconInfo = object
    magic: string
    protocolVersion: uint16
    serverUuid: UuidBytes
    sessionUuid: UuidBytes
    tcpPort: uint16
    udpPort: uint16
    serverName: string

proc readU16(payload: string, offset: var int): uint16 =
  if offset + 2 > payload.len:
    raise newException(ValueError, "unexpected end of payload while reading u16")
  result = (uint16(ord(payload[offset])) shl 8) or uint16(ord(payload[offset + 1]))
  inc(offset, 2)

proc readUuid(payload: string, offset: var int): UuidBytes =
  if offset + result.len > payload.len:
    raise newException(ValueError, "unexpected end of payload while reading uuid")
  for index in 0 ..< result.len:
    result[index] = byte(ord(payload[offset + index]))
  inc(offset, result.len)

proc readString(payload: string, offset: var int): string =
  let length = int(readU16(payload, offset))
  if offset + length > payload.len:
    raise newException(ValueError, "unexpected end of payload while reading string")
  result = payload[offset ..< offset + length]
  inc(offset, length)

proc decodeBeacon(payload: string): BeaconInfo =
  var offset = 0
  if payload.len < 42:
    raise newException(ValueError, "payload is too short to be a beacon")

  result.magic = payload[offset ..< offset + 4]
  inc(offset, 4)
  result.protocolVersion = readU16(payload, offset)
  result.serverUuid = readUuid(payload, offset)
  result.sessionUuid = readUuid(payload, offset)
  result.tcpPort = readU16(payload, offset)
  result.udpPort = readU16(payload, offset)
  result.serverName = readString(payload, offset)

  if offset != payload.len:
    raise newException(ValueError, &"payload has {payload.len - offset} trailing byte(s)")

proc uuidToHex(value: UuidBytes): string =
  result = newStringOfCap(32)
  for item in value:
    result.add(toHex(item, 2))

proc quotePrintable(value: string): string =
  result = "\""
  for ch in value:
    case ch
    of '\n':
      result.add("\\n")
    of '\r':
      result.add("\\r")
    of '\t':
      result.add("\\t")
    else:
      if ord(ch) < 32 or ord(ch) > 126:
        result.add("\\x")
        result.add(toHex(ord(ch), 2))
      else:
        result.add(ch)
  result.add('"')

proc inlineHex(payload: string): string =
  result = newStringOfCap(payload.len * 3)
  for index, ch in payload:
    if index > 0:
      result.add(' ')
    result.add(toHex(ord(ch), 2))

proc hexDump(payload: string, width = 16): string =
  var offset = 0
  while offset < payload.len:
    let lineEnd = min(offset + width, payload.len)
    var hexPart = ""
    var asciiPart = ""
    for index in offset ..< offset + width:
      if index < lineEnd:
        let value = ord(payload[index])
        if hexPart.len > 0:
          hexPart.add(' ')
        hexPart.add(toHex(value, 2))
        if value >= 32 and value <= 126:
          asciiPart.add(payload[index])
        else:
          asciiPart.add('.')
      else:
        if hexPart.len > 0:
          hexPart.add(' ')
        hexPart.add("  ")
        asciiPart.add(' ')

    if result.len > 0:
      result.add('\n')
    result.add(&"  {toHex(offset, 4)}  {hexPart}  {asciiPart}")
    inc(offset, width)

proc lookupMacAddress(ip: string): string =
  try:
    let output = execProcess("arp -a", options = {poUsePath, poStdErrToStdOut})
    for rawLine in output.splitLines():
      let line = rawLine.strip()
      if line.len == 0 or line[0] notin {'0' .. '9'}:
        continue
      let columns = line.splitWhitespace()
      if columns.len >= 2 and columns[0] == ip:
        return columns[1].replace("-", ":").toUpperAscii()
  except OSError:
    discard
  "unavailable"

proc localTimestamp(): string =
  now().format("yyyy-MM-dd HH:mm:ss'.'fff")

proc printBanner(port: int, once: bool) =
  echo &"picoplay beacon detector v{UtilityVersion}"
  echo &"Listening on UDP {port}"
  if once:
    echo "Mode: single packet"
  else:
    echo "Mode: continuous"
  echo "Press Ctrl+C to stop."

proc printBeacon(
  index: int,
  sourceIp: string,
  sourcePort: Port,
  sourceMac: string,
  payload: string,
  beacon: BeaconInfo
) =
  echo ""
  echo repeat("=", 72)
  echo &"Beacon #{index}"
  echo &"Observed at:        {localTimestamp()} local"
  echo &"Source IP:          {sourceIp}"
  echo &"Source UDP port:    {uint16(sourcePort)}"
  echo &"Source MAC:         {sourceMac}"
  echo &"Payload size:       {payload.len} bytes"
  echo &"Magic ascii:        {quotePrintable(beacon.magic)}"
  echo &"Magic hex:          {inlineHex(beacon.magic)}"
  echo &"Magic matches:      {beacon.magic == ExpectedMagic}"
  echo &"Protocol version:   {beacon.protocolVersion}"
  echo &"Protocol matches:   {beacon.protocolVersion == ExpectedProtocolVersion} (expected {ExpectedProtocolVersion})"
  echo &"Server UUID:        {uuidToHex(beacon.serverUuid)}"
  echo &"Session UUID:       {uuidToHex(beacon.sessionUuid)}"
  echo &"TCP port:           {beacon.tcpPort}"
  echo &"Beacon UDP port:    {beacon.udpPort}"
  echo &"Server name:        {quotePrintable(beacon.serverName)}"
  echo "Raw payload:"
  echo hexDump(payload)

proc printMalformedPacket(index: int, sourceIp: string, sourcePort: Port, sourceMac: string, payload: string, error: string) =
  echo ""
  echo repeat("=", 72)
  echo &"Packet #{index}"
  echo &"Observed at:        {localTimestamp()} local"
  echo &"Source IP:          {sourceIp}"
  echo &"Source UDP port:    {uint16(sourcePort)}"
  echo &"Source MAC:         {sourceMac}"
  echo &"Payload size:       {payload.len} bytes"
  echo &"Decode status:      malformed beacon ({error})"
  echo "Raw payload:"
  echo hexDump(payload)

proc printUsage() =
  echo "Usage: beacon_detect [--port=37020] [--once]"
  echo ""
  echo "Options:"
  echo "  -p, --port   UDP port to bind. Defaults to the picoplay beacon port."
  echo "  -1, --once   Exit after the first received packet."
  echo "  -h, --help   Show this help text."

proc main() =
  var port = DefaultBeaconPort
  var once = false

  for kind, key, value in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "p", "port":
        if value.len == 0:
          raise newException(ValueError, "missing value for --port")
        port = parseInt(value)
      of "1", "once":
        once = true
      of "h", "help":
        printUsage()
        return
      else:
        raise newException(ValueError, &"unknown option: {key}")
    of cmdEnd:
      break
    else:
      raise newException(ValueError, "positional arguments are not supported")

  if port < 1 or port > 65535:
    raise newException(ValueError, "port must be between 1 and 65535")

  let socket = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
  socket.setSockOpt(OptReuseAddr, true)
  socket.bindAddr(Port(port))

  printBanner(port, once)

  var packetIndex = 0
  try:
    while true:
      var payload = newString(MaxPacketBytes)
      var sourceIp = ""
      var sourcePort: Port
      let received = socket.recvFrom(payload, MaxPacketBytes, sourceIp, sourcePort)
      if received <= 0:
        continue

      inc(packetIndex)
      let sourceMac = lookupMacAddress(sourceIp)
      try:
        let beacon = decodeBeacon(payload)
        printBeacon(packetIndex, sourceIp, sourcePort, sourceMac, payload, beacon)
      except ValueError as exc:
        printMalformedPacket(packetIndex, sourceIp, sourcePort, sourceMac, payload, exc.msg)

      if once:
        break
  finally:
    socket.close()

when isMainModule:
  try:
    main()
  except ValueError as exc:
    stderr.writeLine("error: " & exc.msg)
    quit(QuitFailure)
