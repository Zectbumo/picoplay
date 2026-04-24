import struct


MAGIC = b"PPLY"

PACKET_CLIENT_HELLO = 1
PACKET_INPUT_SNAPSHOT = 2
PACKET_SERVER_HELLO = 100
PACKET_ASSET_MANIFEST = 101
PACKET_ASSET_DATA = 102

CMD_DRAW_IMAGE = 1
CMD_DRAW_ATLAS = 2
CMD_FILL_RECT = 3
CMD_DRAW_TEXT = 4


def pack_packet(packet_type, payload):
    return struct.pack(">BH", packet_type, len(payload)) + payload


def recv_exact(sock, size):
    chunks = bytearray()
    while len(chunks) < size:
        chunk = sock.recv(size - len(chunks))
        if not chunk:
            raise OSError("socket closed")
        chunks.extend(chunk)
    return bytes(chunks)


def recv_packet(sock):
    header = recv_exact(sock, 3)
    packet_type, payload_len = struct.unpack(">BH", header)
    return packet_type, recv_exact(sock, payload_len)


def encode_client_hello(client_uuid):
    payload = bytearray()
    if client_uuid:
        payload.extend(struct.pack(">B", 1))
        payload.extend(client_uuid)
    else:
        payload.extend(struct.pack(">B", 0))
    return pack_packet(PACKET_CLIENT_HELLO, bytes(payload))


def encode_input_snapshot(snapshot):
    return pack_packet(
        PACKET_INPUT_SNAPSHOT,
        struct.pack(
            ">hhBB",
            int(snapshot.get("joystick_x", 0)),
            int(snapshot.get("joystick_y", 0)),
            1 if snapshot.get("button_a") else 0,
            1 if snapshot.get("button_b") else 0,
        ),
    )


def _read_u16(payload, offset):
    return struct.unpack_from(">H", payload, offset)[0], offset + 2


def _read_u32(payload, offset):
    return struct.unpack_from(">I", payload, offset)[0], offset + 4


def _read_i16(payload, offset):
    return struct.unpack_from(">h", payload, offset)[0], offset + 2


def _read_u64(payload, offset):
    return struct.unpack_from(">Q", payload, offset)[0], offset + 8


def _read_string(payload, offset):
    size, offset = _read_u16(payload, offset)
    data = payload[offset : offset + size]
    return data.decode("utf-8"), offset + size


def decode_server_hello(payload):
    offset = 0
    client_uuid = payload[offset : offset + 16]
    offset += 16
    session_uuid = payload[offset : offset + 16]
    offset += 16
    game_version, offset = _read_u16(payload, offset)
    game_title, offset = _read_string(payload, offset)
    tick_hz, offset = _read_u16(payload, offset)
    player_id = payload[offset]
    offset += 1
    return {
        "client_uuid": client_uuid,
        "session_uuid": session_uuid,
        "game_version": game_version,
        "game_title": game_title,
        "tick_hz": tick_hz,
        "player_id": player_id,
    }


def decode_asset_manifest(payload):
    offset = 0
    asset_count, offset = _read_u16(payload, offset)
    manifest = []
    for _ in range(asset_count):
        asset_id, offset = _read_u16(payload, offset)
        asset_type = payload[offset]
        offset += 1
        mod_time, offset = _read_u64(payload, offset)
        size_bytes, offset = _read_u32(payload, offset)
        manifest.append(
            {
                "asset_id": asset_id,
                "asset_type": asset_type,
                "mod_time": mod_time,
                "size_bytes": size_bytes,
            }
        )
    return manifest


def decode_asset_data(payload):
    asset_id = struct.unpack_from(">H", payload, 0)[0]
    mod_time = struct.unpack_from(">Q", payload, 2)[0]
    size_bytes = struct.unpack_from(">I", payload, 10)[0]
    raw = payload[14 : 14 + size_bytes]
    return {
        "asset_id": asset_id,
        "mod_time": mod_time,
        "size_bytes": size_bytes,
        "data": raw,
    }


def decode_beacon(payload):
    offset = 0
    magic = payload[offset : offset + 4]
    offset += 4
    protocol_version, offset = _read_u16(payload, offset)
    server_uuid = payload[offset : offset + 16]
    offset += 16
    session_uuid = payload[offset : offset + 16]
    offset += 16
    port, offset = _read_u16(payload, offset)
    server_name, offset = _read_string(payload, offset)
    return {
        "magic": magic,
        "protocol_version": protocol_version,
        "server_uuid": server_uuid,
        "session_uuid": session_uuid,
        "port": port,
        "server_name": server_name,
    }


def decode_frame_state(payload):
    offset = 0
    state_sequence, offset = _read_u32(payload, offset)
    draw_count, offset = _read_u16(payload, offset)
    commands = []
    for _ in range(draw_count):
        kind = payload[offset]
        offset += 1
        if kind == CMD_DRAW_IMAGE:
            asset_id, offset = _read_u16(payload, offset)
            x, offset = _read_i16(payload, offset)
            y, offset = _read_i16(payload, offset)
            commands.append({"kind": "draw_image", "asset_id": asset_id, "x": x, "y": y})
        elif kind == CMD_DRAW_ATLAS:
            asset_id, offset = _read_u16(payload, offset)
            atlas_index, offset = _read_u16(payload, offset)
            x, offset = _read_i16(payload, offset)
            y, offset = _read_i16(payload, offset)
            commands.append(
                {
                    "kind": "draw_atlas",
                    "asset_id": asset_id,
                    "atlas_index": atlas_index,
                    "x": x,
                    "y": y,
                }
            )
        elif kind == CMD_FILL_RECT:
            x, offset = _read_i16(payload, offset)
            y, offset = _read_i16(payload, offset)
            w, offset = _read_u16(payload, offset)
            h, offset = _read_u16(payload, offset)
            color, offset = _read_u32(payload, offset)
            commands.append({"kind": "fill_rect", "x": x, "y": y, "w": w, "h": h, "color": color})
        elif kind == CMD_DRAW_TEXT:
            x, offset = _read_i16(payload, offset)
            y, offset = _read_i16(payload, offset)
            color, offset = _read_u32(payload, offset)
            text, offset = _read_string(payload, offset)
            commands.append({"kind": "draw_text", "x": x, "y": y, "color": color, "text": text})
        else:
            raise ValueError("unknown draw command kind %r" % (kind,))

    outputs = {
        "led1": payload[offset],
        "led2": payload[offset + 1],
        "neopixel_r": payload[offset + 2],
        "neopixel_g": payload[offset + 3],
        "neopixel_b": payload[offset + 4],
        "buzzer_mode": payload[offset + 5],
        "buzzer_freq_hz": struct.unpack_from(">H", payload, offset + 6)[0],
        "buzzer_duty": struct.unpack_from(">H", payload, offset + 8)[0],
    }
    return {"state_sequence": state_sequence, "commands": commands, "outputs": outputs}
