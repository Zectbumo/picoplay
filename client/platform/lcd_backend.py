import os
import sys

from platform.renderer import Renderer
from platform.io import HardwareIO


def _load_lcd_module():
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    lib_dir = os.path.join(repo_root, "lib")
    if lib_dir not in sys.path:
        sys.path.append(lib_dir)

    try:
        from lib import lcd as lcd_module  # type: ignore
        return lcd_module
    except Exception:
        try:
            import lcd as lcd_module  # type: ignore
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

    def show(self, state, detail=""):
        self.renderer.clear(0x000000)
        self.renderer.draw_text(10, 10, "STATE", 0xFFFFFF)
        self.renderer.draw_text(10, 30, state, 0x57C7FF)
        if detail:
            self.renderer.draw_text(10, 50, detail[:40], 0xFFFFFF)
        self.renderer.present()
