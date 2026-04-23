try:
    from .renderer import Renderer
    from .io import HardwareIO
except ImportError:
    from renderer import Renderer
    from io import HardwareIO


def _load_lcd_module():
    try:
        import lcd as lcd_module  # type: ignore
        return lcd_module
    except Exception:
        try:
            from lib import lcd as lcd_module  # type: ignore
            return lcd_module
        except Exception:
            return None


_lcd = _load_lcd_module()


def _u32_to_rgb(color):
    return ((color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF)


class LcdRenderer(Renderer):
    def __init__(self):
        self.available = _lcd is not None
        if self.available:
            try:
                _lcd.lcd_init()
            except Exception:
                self.available = False

    def clear(self, color):
        if self.available:
            _lcd.lcd_clear(*_u32_to_rgb(color))

    def fill_rect(self, x, y, w, h, color):
        if self.available:
            _lcd.lcd_set_color(*_u32_to_rgb(color))
            _lcd.lcd_fill(int(x), int(y), int(w), int(h))

    def draw_text(self, x, y, text, color):
        if self.available:
            _lcd.lcd_draw_text(int(x), int(y), str(text), _u32_to_rgb(color))

    def draw_image(self, asset_path, x, y):
        # Raw asset dimensions are not part of the current protocol. The sample
        # game only uses FillRect and DrawText, so image rendering is a no-op
        # until a concrete asset format with dimensions is introduced.
        _ = (asset_path, x, y)

    def draw_atlas(self, asset_path, atlas_index, x, y):
        _ = (asset_path, atlas_index, x, y)


class LcdHardwareIO(HardwareIO):
    def __init__(self):
        self.available = _lcd is not None

    def _read_axis(self, axis):
        if not self.available or axis is None:
            return 0
        value = axis.read_u16()
        centered = int(value) - 32768
        return max(-32767, min(32767, centered * 2))

    def _read_button(self, button):
        if not self.available or button is None:
            return False
        try:
            return bool(1 - int(button.value()))
        except Exception:
            return False

    def read_input(self):
        if not self.available:
            return {"joystick_x": 0, "joystick_y": 0, "button_a": False, "button_b": False}
        return {
            "joystick_x": self._read_axis(getattr(_lcd, "joy_x", None)),
            "joystick_y": self._read_axis(getattr(_lcd, "joy_y", None)),
            "button_a": self._read_button(getattr(_lcd, "button_a", None)),
            "button_b": self._read_button(getattr(_lcd, "button_b", None)),
        }

    def apply_outputs(self, outputs):
        if not self.available:
            return

        try:
            _lcd.lcd_rgb_led(outputs.get("neopixel_r", 0), outputs.get("neopixel_g", 0), outputs.get("neopixel_b", 0))
        except Exception:
            pass

        try:
            if outputs.get("buzzer_mode"):
                _lcd.lcd_start_tone(outputs.get("buzzer_freq_hz", 440), outputs.get("buzzer_duty", 0))
            else:
                _lcd.lcd_stop_tone()
        except Exception:
            pass


class StatusDisplay:
    def __init__(self, renderer):
        self.renderer = renderer
        self.wifi_message = "not connected"
        self.beacon_message = "searching"
        self.host_message = "not connected"
        self.auto_select_message = "waiting for beacon"
        self._wait_dots = {"wifi": 0, "beacon": 0, "host": 0}
        self._wait_counts = {"wifi": 0, "beacon": 0, "host": 0}
        self._rendered_lines = {}
        self._init_screen()

    def _init_screen(self):
        self.renderer.clear(0x000000)
        self._draw()

    def _advance_wait(self, key):
        dots = self._wait_dots[key] + 1
        count = self._wait_counts[key]
        if dots > 10:
            dots = 1
            count += 10
        self._wait_dots[key] = dots
        self._wait_counts[key] = count

    def _reset_wait(self, key):
        self._wait_dots[key] = 0
        self._wait_counts[key] = 0

    def _wait_suffix(self, key):
        suffix = "." * self._wait_dots[key]
        if self._wait_counts[key]:
            return "%d %s" % (self._wait_counts[key], suffix)
        return suffix

    def _with_wait(self, label, key):
        suffix = self._wait_suffix(key)
        return "%s %s" % (label, suffix) if suffix else label

    def _line(self, key, y, text, color):
        text = str(text).upper()[:40]
        previous = self._rendered_lines.get(key)
        if previous == (text, color):
            return False

        clear_needed = True
        if previous is not None:
            old_text, old_color = previous
            if color == old_color and text.startswith(old_text):
                clear_needed = False

        if clear_needed:
            self.renderer.fill_rect(0, y - 2, 240, 20, 0x000000)

        self.renderer.draw_text(4, y, text, color)
        self._rendered_lines[key] = (text, color)
        return True

    def _draw(self):
        changed = False
        changed = self._line("wifi", 8, "WiFi: %s" % self.wifi_message, 0x7CFF9A if self.wifi_message.startswith("connected") else 0xFFD166) or changed
        changed = self._line("beacon", 30, "Beacon: %s" % self.beacon_message, 0x57C7FF if self.beacon_message.startswith("found") else 0xFFFFFF) or changed
        changed = self._line("host", 52, "Host: %s" % self.host_message, 0x7CFF9A if self.host_message.startswith("connected") else 0xFFFFFF) or changed
        changed = self._line("auto_select", 74, "Auto-select: %s" % self.auto_select_message, 0xFFFFFF) or changed
        if changed:
            self.renderer.present()

    def set_wifi_message(self, ssid):
        if ssid:
            self.wifi_message = "connected %s" % ssid
            self._reset_wait("wifi")
        else:
            self.wifi_message = "not connected"
            self._reset_wait("wifi")
        self._draw()

    def show(self, state, detail=""):
        if state == "CONNECTING_WIFI":
            self._advance_wait("wifi")
            self.wifi_message = self._with_wait(detail or "connecting", "wifi")
            self.host_message = "not connected"
            self.beacon_message = "searching"
            self.auto_select_message = "waiting for beacon"
        elif state == "BEACON_SEARCHING":
            self._advance_wait("beacon")
            self.beacon_message = self._with_wait("searching", "beacon")
            self._advance_wait("host")
            self.host_message = self._with_wait("not connected", "host")
            self.auto_select_message = "waiting for beacon"
        elif state == "BEACON_FOUND":
            self._reset_wait("beacon")
            self.beacon_message = "found %s" % detail if detail else "found"
            self.host_message = self._with_wait("not connected", "host")
            if self.auto_select_message == "waiting for beacon":
                self.auto_select_message = ".......... 1010ms"
        elif state == "AUTO_SELECT_COUNTDOWN":
            remaining_ms = detail or "0"
            try:
                remaining_value = int(remaining_ms)
            except ValueError:
                remaining_value = 0
            dots = int((remaining_value + 99) / 100) if remaining_value > 0 else 0
            if dots < 0:
                dots = 0
            if dots > 10:
                dots = 10
            self._advance_wait("host")
            self.host_message = self._with_wait("not connected", "host")
            self.auto_select_message = "%s %sms" % ("." * dots, remaining_value)
        elif state == "AUTO_SELECT_MULTIPLE":
            self.auto_select_message = "multiple sessions"
        elif state == "READY":
            self._reset_wait("host")
            self.host_message = "connected %s" % (detail or "ready")
            self.auto_select_message = "complete"
        elif state == "DISCONNECTED":
            self._advance_wait("host")
            self.host_message = self._with_wait("not connected", "host")
            self.auto_select_message = "waiting for beacon"

        self._draw()
