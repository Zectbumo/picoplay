import os

try:
    from secrets import ssid as WIFI_SSID, password as WIFI_PASSWORD
except ImportError:
    WIFI_SSID = ""
    WIFI_PASSWORD = ""


PROTOCOL_VERSION = 2
GAME_VERSION = 2
BEACON_PORT = 37020
TCP_CONNECT_TIMEOUT_S = 5.0
FRAME_IDLE_TIMEOUT_S = 5.0
RECONNECT_DELAY_S = 1.0
DISCOVERY_TIMEOUT_MS = 1010


def _dirname(path):
    if "/" not in path:
        return ""
    return path.rsplit("/", 1)[0]


def _ensure_dir(path):
    if not path:
        return
    parts = path.split("/")
    current = ""
    for part in parts:
        if not part:
            continue
        current = part if not current else current + "/" + part
        try:
            os.mkdir(current)
        except OSError:
            pass

CLIENT_UUID_PATH = "client_uuid.txt"
ASSET_DIR = "assets"
ASSET_MANIFEST_PATH = ASSET_DIR + "/manifest.dat"


def load_client_uuid():
    try:
        with open(CLIENT_UUID_PATH, "r") as handle:
            value = handle.read().strip()
            return bytes.fromhex(value) if value else None
    except OSError:
        return None


def save_client_uuid(client_uuid):
    _ensure_dir(_dirname(CLIENT_UUID_PATH))
    with open(CLIENT_UUID_PATH, "w") as handle:
        handle.write(client_uuid.hex())
