# picoplay

**picoplay** is a LAN multiplayer system with an authoritative Nim server and ultra-thin MicroPython clients (Raspberry Pi Pico 2 W).

The server owns all game logic, assets, and frame rendering decisions. Clients act as simple input/output devices: they render exactly what the server tells them and report input state after each frame.

This project is intentionally minimal (MVP) and optimized for simplicity, determinism, and low overhead.

---

# Core Principles

- Server is fully authoritative
- Clients are “dumb terminals”
- No security, no validation, no compression (trusted LAN)
- Fixed binary protocol (no dynamic schemas)
- No delta frames or prediction
- Full frame sent every tick (KISS)
- Up to 4 players
- Target: 60 FPS

---

# System Overview

## Server (Nim)

Responsibilities:

- Broadcast presence via UDP beacon (1s interval)
- Accept TCP connections
- Assign players (1–4)
- Maintain authoritative game state
- Manage asset catalog
- Synchronize assets to clients
- Build and send full frame commands every tick
- Receive input snapshots from clients

## Client (MicroPython, Pico 2 W)

Responsibilities:

- Connect to Wi-Fi
- Discover servers via UDP beacon
- Auto-select or present server selection UI
- Maintain local asset cache
- Download assets from server
- Render frame commands exactly as received
- Drive outputs:
  - LCD display
  - 2 LEDs
  - RGB neopixel
  - PWM buzzer
- Sample inputs:
  - Joystick (X, Y)
  - Button A, Button B
- Send one input snapshot per rendered frame
- Reconnect automatically on disconnect

---

# Network Model

## Discovery

- UDP broadcast beacon every **1 second**

## Session / Runtime

- TCP only
- No UDP gameplay traffic

## Reconnect Behavior

- Immediate reconnect attempt on disconnect
- Then retry every **1 second**
- Stop reconnecting if beacon indicates incompatible version

---

# Identity

## UUIDs

- Server has permanent UUID
- Client has permanent UUID (stored locally)
- Session has UUID (per connection)

UUIDs are **not used in high-frequency packets**

## Client UUID Generation

If client has no UUID:

1. Client connects without UUID
2. Server sends current time
3. Client generates UUID using:
   - server time
   - MAC address (if available)
   - random entropy
4. Client stores UUID locally
5. Client reconnects

---

# Discovery Protocol (Beacon)

Broadcast every 1 second.

## Fields

- `protocol_version` (u16)
- `game_version` (u16)
- `server_uuid` (16 bytes)
- `tcp_port` (u16)
- `server_name` (string)
- `game_title` (string)

## Compatibility Rules

Client accepts a server only if:

- protocol_version matches
- game_version matches
- game_title matches

## Selection Logic

- Start 1010 ms timer on first beacon
- If **1 compatible server** → auto-select
- If **multiple** → show selection UI
- No persistence of preferred server

---

# Asset System

## Server is Source of Truth

Clients must match server asset catalog exactly.

## Asset Identity

Each asset:

- `asset_id` (u16)
- `asset_type` (u8)
- `mod_time` (u64)
- `size_bytes` (u32)

## Atlas Support

- `asset_id` (u16)
- `atlas_index` (u16)

## Sync Process

On connect:

1. Server sends BOM (bill of materials)
2. Client:
   - deletes all local assets not in BOM
   - deletes assets with mismatched `mod_time`
3. Client downloads required assets (one at a time)
4. No checksum
5. No resume
6. No chunking

---

# Client Storage Layout

```
/config.dat
/client_uuid.txt
/assets/
/assets/catalog.dat
/assets/<asset_id>.bin
```

---

# Runtime Model

## Server Loop (60 FPS)

Each tick:

1. Read latest input per player
2. Update game state
3. Build frame commands
4. Send full frame to each client

## Client Loop

1. Receive frame
2. Render immediately
3. Apply outputs (LEDs, buzzer, etc.)
4. Sample input
5. Send input snapshot
6. Repeat

---

# Protocol

## Transport

- TCP
- Binary packets
- Fixed layout (struct-compatible)

## Packet Framing

```
packet_type: u8
payload_length: u16
payload_bytes
```

---

# Packet Types

## Client → Server

### ClientHello

- `client_uuid_present` (u8)
- `client_uuid` (16 bytes if present)

---

### InputSnapshot

- `joystick_x` (i16)
- `joystick_y` (i16)
- `button_a` (u8)
- `button_b` (u8)

---

## Server → Client

### TimeSeed

- `unix_time` (u64)

---

### ServerHello

- `session_uuid` (16 bytes)
- `player_number` (u8)

---

### AssetBom

- `asset_count` (u16)
- repeated:
  - `asset_id` (u16)
  - `asset_type` (u8)
  - `mod_time` (u64)
  - `size_bytes` (u32)

---

### AssetData

- `asset_id` (u16)
- `mod_time` (u64)
- `size_bytes` (u32)
- raw bytes follow

---

### StartGame

- no payload

---

### Frame

- `draw_count` (u16)
- draw commands...
- `led1` (u8)
- `led2` (u8)
- `neopixel_r` (u8)
- `neopixel_g` (u8)
- `neopixel_b` (u8)
- `buzzer_mode` (u8)
- `buzzer_freq_hz` (u16)
- `buzzer_duty` (u16)

---

# Draw Commands

Executed in order (implicit Z-order).

## DrawImage

- `asset_id` (u16)
- `x` (i16)
- `y` (i16)

## DrawAtlas

- `asset_id` (u16)
- `atlas_index` (u16)
- `x` (i16)
- `y` (i16)

## FillRect

- `x` (i16)
- `y` (i16)
- `w` (u16)
- `h` (u16)
- `color` (u16/u32)

---

# Outputs (per frame)

- LED1, LED2
- RGB neopixel
- PWM buzzer (mode, frequency, duty)

---

# Input Model

Client sends exactly one snapshot per frame:

- joystick X/Y
- button A/B

No timestamps  
No sequence IDs  
No frame IDs  

---

# Server Architecture (Nim)

```
server/
  src/
    main.nim
    config.nim
    uuid_util.nim
    beacon.nim
    tcp_server.nim
    session_manager.nim
    asset_catalog.nim
    asset_sync.nim
    protocol_encode.nim
    protocol_decode.nim
    game/
      game_state.nim
      game_rules.nim
      frame_builder.nim
    runtime/
      loop.nim
```

---

# Client Architecture (MicroPython)

```
client/
  boot.py
  main.py
  config.py
  uuid_util.py
  wifi.py
  beacon.py
  select_server.py
  tcp_client.py
  asset_store.py
  asset_sync.py
  render.py
  display_driver.py
  input.py
  output.py
```

---

# Sample MVP Game

Minimal validation game:

- 4 players
- top-down movement
- joystick controls movement
- button A triggers sound/flash
- button B changes color
- server sends full frame every tick

---

# Non-Goals (MVP)

Not included:

- security
- encryption
- validation
- internet play
- NAT traversal
- compression
- delta frames
- keyframes
- asset checksums
- resumable downloads
- capability negotiation
- preferred server storage
- interpolation
- prediction

---

# Implementation Order

1. Protocol definitions
2. Beacon (server + client)
3. TCP handshake + player assignment
4. UUID generation flow
5. Asset BOM + purge
6. Asset download
7. Frame packet + renderer
8. Input snapshot
9. Game loop (server)
10. Reconnect logic
11. Sample game

---

# Summary

picoplay is designed to be:

- extremely simple
- deterministic
- easy to implement on constrained hardware
- easy to reason about

The system trades bandwidth efficiency for clarity and reliability, making it ideal for LAN-based embedded multiplayer systems.

---

# Optimization Notes

- Use `struct.pack_into` / `unpack_from` on MicroPython to avoid allocations
- Preallocate buffers for frame parsing
- Avoid building intermediate objects when rendering
- Keep asset IDs stable across builds using a manifest

