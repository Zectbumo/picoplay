try:
    import usocket as socket
except ImportError:  # pragma: no cover - desktop fallback
    import socket

try:
    import uselect as select
except ImportError:  # pragma: no cover - desktop fallback
    import select

try:
    import utime as time
except ImportError:  # pragma: no cover - desktop fallback
    import time

import config
import protocol


def discover(timeout_ms=None, status_cb=None):
    timeout_ms = config.DISCOVERY_TIMEOUT_MS if timeout_ms is None else timeout_ms
    sessions = {}
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("", config.BEACON_PORT))
    poller = select.poll() if hasattr(select, "poll") else None
    if poller is not None:
        poller.register(sock, select.POLLIN)

    deadline = time.ticks_add(time.ticks_ms(), timeout_ms) if hasattr(time, "ticks_add") else (time.time() + timeout_ms / 1000.0)
    try:
        while True:
            if hasattr(time, "ticks_diff"):
                remaining = time.ticks_diff(deadline, time.ticks_ms())
                if remaining <= 0:
                    break
            else:
                remaining = int((deadline - time.time()) * 1000)
                if remaining <= 0:
                    break

            if status_cb:
                status_cb("FINDING_BEACON", "listening")

            ready = poller.poll(remaining) if poller is not None else select.select([sock], [], [], remaining / 1000.0)[0]
            if not ready:
                break

            payload, address = sock.recvfrom(1024)
            beacon = protocol.decode_beacon(payload)
            if beacon["magic"] != protocol.MAGIC or beacon["protocol_version"] != config.PROTOCOL_VERSION:
                continue
            key = beacon["session_uuid"].hex()
            beacon["address"] = address[0]
            sessions[key] = beacon
            if status_cb:
                status_cb("FINDING_BEACON", beacon["server_name"])
    finally:
        sock.close()

    return list(sessions.values())
