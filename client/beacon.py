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


def _now_ms():
    if hasattr(time, "ticks_ms"):
        return time.ticks_ms()
    return int(time.time() * 1000)


def _add_ms(start_ms, delta_ms):
    if hasattr(time, "ticks_add"):
        return time.ticks_add(start_ms, delta_ms)
    return start_ms + delta_ms


def _diff_ms(end_ms, start_ms):
    if hasattr(time, "ticks_diff"):
        return time.ticks_diff(end_ms, start_ms)
    return end_ms - start_ms


def discover(timeout_ms=None, status_cb=None):
    timeout_ms = config.DISCOVERY_TIMEOUT_MS if timeout_ms is None else timeout_ms
    poll_slice_ms = 100
    sessions = {}
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", config.BEACON_PORT))
    poller = select.poll() if hasattr(select, "poll") else None
    if poller is not None:
        poller.register(sock, select.POLLIN)

    try:
        selection_deadline = None
        while True:
            if selection_deadline is None:
                remaining = timeout_ms
                if status_cb:
                    status_cb("BEACON_SEARCHING", "")
            else:
                remaining = _diff_ms(selection_deadline, _now_ms())
                if remaining <= 0:
                    break
                if status_cb:
                    status_cb("AUTO_SELECT_COUNTDOWN", str(remaining))

            wait_ms = poll_slice_ms if selection_deadline is None or remaining > poll_slice_ms else remaining
            ready = poller.poll(wait_ms) if poller is not None else select.select([sock], [], [], wait_ms / 1000.0)[0]
            if not ready:
                continue

            payload, address = sock.recvfrom(1024)
            beacon = protocol.decode_beacon(payload)
            if beacon["magic"] != protocol.MAGIC or beacon["protocol_version"] != config.PROTOCOL_VERSION:
                continue
            key = beacon["session_uuid"].hex()
            beacon["address"] = address[0]
            sessions[key] = beacon
            if status_cb:
                status_cb("BEACON_FOUND", "%s @ %s" % (beacon["server_name"], address[0]))
            if selection_deadline is None:
                selection_deadline = _add_ms(_now_ms(), timeout_ms)
    finally:
        sock.close()

    if len(sessions) > 1 and status_cb:
        status_cb("AUTO_SELECT_MULTIPLE", str(len(sessions)))
    return list(sessions.values())
