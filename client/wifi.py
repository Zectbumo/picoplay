try:
    import network as _network
    import utime as _time
except ImportError:  # pragma: no cover - desktop fallback
    _network = None
    import time as _time

import config


def connect(status_cb=None, ssid=None, password=None, timeout_s=15):
    ssid = ssid if ssid is not None else config.WIFI_SSID
    password = password if password is not None else config.WIFI_PASSWORD

    if status_cb:
        status_cb("CONNECTING_WIFI", "starting")

    if _network is None:
        if status_cb:
            status_cb("CONNECTING_WIFI", "desktop stub")
        return {"connected": True, "ip": "127.0.0.1"}

    wlan = _network.WLAN(_network.STA_IF)
    wlan.active(True)
    if wlan.isconnected():
        return {"connected": True, "ip": wlan.ifconfig()[0]}

    if not ssid:
        raise RuntimeError("WIFI_SSID is not configured")

    wlan.connect(ssid, password)
    start = _time.time()
    while not wlan.isconnected():
        if status_cb:
            status_cb("CONNECTING_WIFI", "joining %s" % ssid)
        if _time.time() - start > timeout_s:
            raise RuntimeError("Wi-Fi connection timed out")
        _time.sleep(0.25)

    return {"connected": True, "ip": wlan.ifconfig()[0]}
