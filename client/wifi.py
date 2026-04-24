try:
    import network as _network
    import utime as _time
except ImportError:  # pragma: no cover - desktop fallback
    _network = None
    import time as _time

import config


def _ipv4_to_int(value):
    parts = value.split(".")
    if len(parts) != 4:
        return 0
    result = 0
    for part in parts:
        result = (result << 8) | (int(part) & 0xFF)
    return result


def _int_to_ipv4(value):
    return ".".join(str((value >> shift) & 0xFF) for shift in (24, 16, 8, 0))


def _broadcast_ip(ip, netmask):
    return _int_to_ipv4(_ipv4_to_int(ip) | (~_ipv4_to_int(netmask) & 0xFFFFFFFF))


def _wifi_info(ssid, ifconfig):
    ip, netmask, gateway, dns = ifconfig
    return {
        "connected": True,
        "ip": ip,
        "netmask": netmask,
        "gateway": gateway,
        "dns": dns,
        "broadcast": _broadcast_ip(ip, netmask),
        "ssid": ssid,
    }


def is_connected():
    if _network is None:
        return True

    wlan = _network.WLAN(_network.STA_IF)
    return bool(wlan.active() and wlan.isconnected())


def connect(status_cb=None, ssid=None, password=None, timeout_s=15):
    ssid = ssid if ssid is not None else config.WIFI_SSID
    password = password if password is not None else config.WIFI_PASSWORD

    if _network is None:
        if status_cb:
            status_cb("CONNECTING_WIFI", "desktop stub")
        return _wifi_info(ssid or "desktop", ("127.0.0.1", "255.0.0.0", "127.0.0.1", "127.0.0.1"))

    wlan = _network.WLAN(_network.STA_IF)
    wlan.active(True)
    if wlan.isconnected():
        current_ssid = ssid
        try:
            current_ssid = wlan.config("ssid") or ssid
        except Exception:
            pass
        return _wifi_info(current_ssid, wlan.ifconfig())

    if not ssid:
        raise RuntimeError("Wi-Fi credentials are not configured in secrets.py")

    if status_cb:
        status_cb("CONNECTING_WIFI", "joining %s" % ssid)

    wlan.connect(ssid, password)
    start = _time.time()
    while not wlan.isconnected():
        if status_cb:
            status_cb("CONNECTING_WIFI", "joining %s" % ssid)
        if _time.time() - start > timeout_s:
            raise RuntimeError("Wi-Fi connection timed out")
        _time.sleep(0.25)

    current_ssid = ssid
    try:
        current_ssid = wlan.config("ssid") or ssid
    except Exception:
        pass
    return _wifi_info(current_ssid, wlan.ifconfig())
