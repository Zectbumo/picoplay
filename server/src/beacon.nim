import config, protocol

proc buildBeaconPayload*(
  cfg: ServerConfig,
  serverUuid: UuidBytes,
  sessionUuid: UuidBytes
): string =
  encodeBeacon(
    cfg.protocolVersion,
    serverUuid,
    sessionUuid,
    cfg.tcpPort,
    cfg.udpPort,
    cfg.serverName
  )
