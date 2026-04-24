try:
    import ujson as json
except ImportError:  # pragma: no cover - desktop fallback
    import json

import os

import config
import protocol


def _ensure_asset_dir():
    try:
        os.mkdir(config.ASSET_DIR)
    except OSError:
        pass


def load_manifest():
    try:
        with open(config.ASSET_MANIFEST_PATH, "r") as handle:
            return json.load(handle)
    except OSError:
        return []


def save_manifest(manifest):
    _ensure_asset_dir()
    with open(config.ASSET_MANIFEST_PATH, "w") as handle:
        json.dump(manifest, handle)


def _asset_path(asset_id):
    return "%s/%s.bin" % (config.ASSET_DIR, asset_id)


def sync_from_control_socket(sock, status_cb=None):
    packet_type, payload = protocol.recv_packet(sock)
    if packet_type != protocol.PACKET_ASSET_MANIFEST:
        raise RuntimeError("expected AssetManifest packet")

    manifest = protocol.decode_asset_manifest(payload)
    if status_cb:
        status_cb("SYNCING_ASSETS", "manifest %d assets" % len(manifest))

    _ensure_asset_dir()
    expected_ids = {entry["asset_id"] for entry in manifest}
    for entry in os.listdir(config.ASSET_DIR):
        if not entry.endswith(".bin"):
            continue
        asset_id = int(entry.split(".", 1)[0])
        if asset_id not in expected_ids:
            os.remove("%s/%s" % (config.ASSET_DIR, entry))

    for index, entry in enumerate(manifest, start=1):
        packet_type, payload = protocol.recv_packet(sock)
        if packet_type != protocol.PACKET_ASSET_DATA:
            raise RuntimeError("expected AssetData packet")
        asset = protocol.decode_asset_data(payload)
        with open(_asset_path(asset["asset_id"]), "wb") as handle:
            handle.write(asset["data"])
        if status_cb:
            status_cb("SYNCING_ASSETS", "%d/%d" % (index, len(manifest)))

    save_manifest(manifest)
    return manifest
