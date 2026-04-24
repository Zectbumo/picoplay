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
    cfg.port,
    cfg.serverName
  )
