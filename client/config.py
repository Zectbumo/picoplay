import os


PROTOCOL_VERSION = 1
GAME_VERSION = 1
BEACON_PORT = 37020
CLIENT_UDP_PORT = 37021
TCP_CONNECT_TIMEOUT_S = 5.0
FRAME_IDLE_TIMEOUT_S = 5.0
RECONNECT_DELAY_S = 1.0
DISCOVERY_TIMEOUT_MS = 1010

WIFI_SSID = os.getenv("PICOPLAY_WIFI_SSID", "")
WIFI_PASSWORD = os.getenv("PICOPLAY_WIFI_PASSWORD", "")

BASE_DIR = os.path.dirname(__file__) or "."
CLIENT_UUID_PATH = os.path.join(BASE_DIR, "client_uuid.txt")
ASSET_DIR = os.path.join(BASE_DIR, "assets")
ASSET_MANIFEST_PATH = os.path.join(ASSET_DIR, "manifest.dat")


def load_client_uuid():
    try:
        with open(CLIENT_UUID_PATH, "r", encoding="ascii") as handle:
            value = handle.read().strip()
            return bytes.fromhex(value) if value else None
    except OSError:
        return None


def save_client_uuid(client_uuid):
    os.makedirs(os.path.dirname(CLIENT_UUID_PATH) or ".", exist_ok=True)
    with open(CLIENT_UUID_PATH, "w", encoding="ascii") as handle:
        handle.write(client_uuid.hex())
