try:
    import utime as time
except ImportError:  # pragma: no cover - desktop fallback
    import time

import config
import wifi
import beacon
import network
from platform.lcd_backend import LcdRenderer, LcdHardwareIO, StatusDisplay


def _sleep(seconds):
    if hasattr(time, "sleep"):
        time.sleep(seconds)
    else:  # pragma: no cover
        time.sleep_ms(int(seconds * 1000))


def _format_wifi_report(wifi_info):
    return "ip=%s netmask=%s broadcast=%s" % (
        wifi_info.get("ip", ""),
        wifi_info.get("netmask", ""),
        wifi_info.get("broadcast", ""),
    )


def _set_status_wifi_message(status_display, message):
    if hasattr(status_display, "set_wifi_message"):
        status_display.set_wifi_message(message)
        return

    # Allow older StatusDisplay implementations that only expose the backing
    # attribute so the connection loop still runs on partially updated clients.
    status_display.wifi_message = message or "not connected"


def run():
    renderer = LcdRenderer()
    io_backend = LcdHardwareIO()
    status_display = StatusDisplay(renderer)

    def status_cb(state, detail=""):
        print("[%s] %s" % (state, detail))
        status_display.show(state, detail)

    while True:
        try:
            wifi_info = wifi.connect(status_cb=status_cb)
            status_cb("WIFI_CONNECTED", _format_wifi_report(wifi_info))
        except Exception as exc:
            status_cb("DISCONNECTED", str(exc))
            _sleep(config.RECONNECT_DELAY_S)
            continue

        while True:
            connection = None
            try:
                sessions = beacon.discover(status_cb=status_cb)
                if not sessions:
                    continue
                if len(sessions) != 1:
                    _sleep(config.RECONNECT_DELAY_S)
                    continue

                selected = sessions[0]
                connection = network.open_session(selected, status_cb=status_cb)
                status_cb("READY", "player %d" % connection.server_hello["player_id"])

                while True:
                    frame = connection.recv_frame(timeout_ms=100)
                    if frame is not None:
                        renderer.clear(0x000000)
                        for command in frame["commands"]:
                            kind = command["kind"]
                            if kind == "fill_rect":
                                renderer.fill_rect(command["x"], command["y"], command["w"], command["h"], command["color"])
                            elif kind == "draw_text":
                                renderer.draw_text(command["x"], command["y"], command["text"], command["color"])
                        renderer.present()
                        io_backend.apply_outputs(frame["outputs"])

                    connection.send_input(io_backend.read_input())
            except Exception as exc:
                status_cb("DISCONNECTED", str(exc))
                if connection is not None:
                    try:
                        connection.close()
                    except Exception:
                        pass

                if not wifi.is_connected():
                    _set_status_wifi_message(status_display, "")
                    break

                _sleep(config.RECONNECT_DELAY_S)


if __name__ == "__main__":
    run()
