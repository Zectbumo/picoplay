# picoplay

**picoplay** is a LAN multiplayer system with an authoritative Nim server and MicroPython clients running on Raspberry Pi Pico 2 W hardware.

The server owns simulation, player assignment, and asset distribution. Clients handle Wi-Fi, discovery, asset caching, rendering, local I/O, and connection status display.

The design goal is a simple LAN system with a fixed binary protocol and minimal moving parts.

---

# Principles

- Server is authoritative
- Clients stay thin and deterministic
- `TCP` handles control and asset transfer
- `UDP` handles discovery and per-client frame state delivery
- Rendering and hardware I/O stay behind small client-side interfaces
- No security, compression, dynamic schemas, rollback, or prediction

---

# Runtime

## Server

- Broadcast a UDP beacon every 1 second
- Accept TCP control connections
- Issue a client UUID when a client does not already have one
- Assign player IDs
- Send the asset manifest and asset data over TCP
- Receive input snapshots over TCP
- Simulate game state at configurable `tick_hz`
- Send the latest frame state over UDP to each client

## Client

- Connect to Wi-Fi
- Find servers from UDP beacons
- Open a TCP control session
- Sync local assets from the server
- Listen for UDP frame state updates
- Render the newest state immediately
- Read local input and send snapshots over TCP
- Reclaim the same player ID if reconnect happens within 5 seconds
- Reconnect automatically after disconnect

---

# Client Status Flow

The Pico should visibly report its startup and reconnect state:

1. `CONNECTING_WIFI`
2. `FINDING_BEACON`
3. `SYNCING_ASSETS`
4. `READY`
5. `DISCONNECTED`

Expected behavior:

- Wi-Fi screen shows SSID and retry state
- Beacon screen shows scan progress and the most recent discovered session
- Asset sync screen shows counts or bytes downloaded
- Ready state shows game output
- Disconnect state shows reconnect progress and falls back through the same flow

---

# Client Platform

The client should be library agnostic at the architecture level. It needs two interfaces.

## Renderer

A renderer backend should be able to:

- initialize hardware
- clear the screen
- draw rectangles
- draw text
- draw images or atlas regions

## Hardware I/O

A hardware backend should be able to:

- read joystick X/Y
- read button A and button B
- set indicator outputs
- set neopixel color
- start and stop buzzer tones

Any display/input library can be used if it satisfies those interfaces.

---

# Working Pico Implementation

The initial Pico implementation can use `lib/lcd.py` for the concrete display and input bindings while keeping the higher-level client code abstracted behind renderer and I/O adapters.

Useful mappings from `lib/lcd.py`:

- `lcd_init()` for display setup
- `lcd_clear()` for full-screen clear
- `lcd_set_color()` and `lcd_fill()` for filled rectangles
- `lcd_draw_text()` for status and game text
- `lcd_blit_file()` for image blits
- `lcd_rgb_led()` for neopixel output
- `lcd_start_tone()` and `lcd_stop_tone()` for buzzer control
- `joy_x`, `joy_y`, `button_a`, and `button_b` for local inputs

This gives a complete working Pico client without making the overall platform depend on that module.

---

# Identity

- Server has a persistent UUID
- Client has a persistent UUID stored locally
- Each TCP session has its own session UUID

If a client has no UUID:

1. Open TCP control without a UUID
2. Receive a server-issued client UUID
3. Store it locally
4. Continue the same session with that UUID

UUIDs are not used in UDP frame state packets.

If a client disconnects unexpectedly, its player ID remains reserved for 5 seconds before being released.

---

# Discovery

The server broadcasts a UDP beacon every 1 second.

Beacon fields:

- `magic` (`4 bytes`)
- `protocol_version` (`u16`)
- `server_uuid` (`16 bytes`)
- `session_uuid` (`16 bytes`)
- `tcp_port` (`u16`)
- `udp_port` (`u16`)
- `server_name` (string)

Client accepts a beacon only if `magic` and `protocol_version` both match.

Selection behavior:

- Start a 1010 ms timer after the first compatible beacon
- Auto-select if there is exactly one discovered session
- Show selection UI if there are multiple discovered sessions

---

# Asset Sync

The server is the source of truth for assets.

Each asset has:

- `asset_id` (`u16`)
- `asset_type` (`u8`)
- `mod_time` (`u64`)
- `size_bytes` (`u32`)

Atlas entries use:

- `asset_id` (`u16`)
- `atlas_index` (`u16`)

Use `asset manifest` as the single term for the list of assets and their metadata.

Sync flow over TCP:

1. Server sends the asset manifest
2. Client deletes local assets not in the asset manifest
3. Client deletes assets with mismatched `mod_time`
4. Client downloads required assets one at a time
5. Client updates the local asset manifest
6. Client enters `READY`

Storage layout:

```text
/config.dat
/client_uuid.txt
/assets/
/assets/manifest.dat
/assets/<asset_id>.bin
```

---

# Protocol

Transport split:

- `UDP`: beacon discovery and per-client frame state delivery
- `TCP`: handshake, asset sync, input, and session control

TCP packet framing:

```text
packet_type: u8
payload_length: u16
payload_bytes
```

UDP packets use fixed binary layouts without stream framing.

## Client -> Server (`TCP`)

### `ClientHello`

- `client_uuid_present` (`u8`)
- `client_uuid` (`16 bytes`, if present)

### `InputSnapshot`

- `joystick_x` (`i16`)
- `joystick_y` (`i16`)
- `button_a` (`u8`)
- `button_b` (`u8`)

## Server -> Client (`TCP`)

### `ServerHello`

- `client_uuid` (`16 bytes`)
- `session_uuid` (`16 bytes`)
- `game_version` (`u16`)
- `game_title` (string)
- `tick_hz` (`u16`)
- `player_id` (`u8`)
- `udp_port` (`u16`)

### `AssetManifest`

- `asset_count` (`u16`)
- repeated asset entries:
  - `asset_id` (`u16`)
  - `asset_type` (`u8`)
  - `mod_time` (`u64`)
  - `size_bytes` (`u32`)

### `AssetData`

- `asset_id` (`u16`)
- `mod_time` (`u64`)
- `size_bytes` (`u32`)
- raw asset bytes

## Server -> Client (`UDP`)

### `Beacon`

- `magic` (`4 bytes`)
- `protocol_version` (`u16`)
- `server_uuid` (`16 bytes`)
- `session_uuid` (`16 bytes`)
- `tcp_port` (`u16`)
- `udp_port` (`u16`)
- `server_name` (string)

### `FrameState`

- `state_sequence` (`u32`)
- `draw_count` (`u16`)
- draw commands
- `led1` (`u8`)
- `led2` (`u8`)
- `neopixel_r` (`u8`)
- `neopixel_g` (`u8`)
- `neopixel_b` (`u8`)
- `buzzer_mode` (`u8`)
- `buzzer_freq_hz` (`u16`)
- `buzzer_duty` (`u16`)

The client keeps only the newest `FrameState` packet and may drop older or out-of-order packets.

## Draw Commands

### `DrawImage`

- `asset_id` (`u16`)
- `x` (`i16`)
- `y` (`i16`)

### `DrawAtlas`

- `asset_id` (`u16`)
- `atlas_index` (`u16`)
- `x` (`i16`)
- `y` (`i16`)

### `FillRect`

- `x` (`i16`)
- `y` (`i16`)
- `w` (`u16`)
- `h` (`u16`)
- `color` (`u32`)

### `DrawText`

- `x` (`i16`)
- `y` (`i16`)
- `color` (`u32`)
- `text_id` or inline string

---

# Input And Outputs

Client sends one `InputSnapshot` per local loop iteration over TCP.

Frame state updates carry output state for:

- indicator LEDs
- RGB neopixel
- buzzer mode, frequency, and duty

---

# Project Shape

```text
server/
  src/
    main.nim
    config.nim
    beacon.nim
    network.nim
    assets.nim
    protocol.nim
    game.nim

client/
  boot.py
  main.py
  config.py
  wifi.py
  beacon.py
  network.py
  assets.py
  protocol.py
  platform/
    renderer.py
    io.py
    lcd_backend.py
```

---

# Server Build And Run

From the repo root:

Debug build:

```powershell
nim c --threads:on --out:server/picoplay_server.exe server/src/main.nim
```

Release build:

```powershell
nim c -d:release --threads:on --out:server/picoplay_server.exe server/src/main.nim
```

Run the server:

```powershell
.\server\picoplay_server.exe
```

The server stores its generated UUID in `server/server_uuid.txt` and serves assets from `server/assets/`.

---

# Sample Game

- up to 4 players
- top-down movement
- joystick controls movement
- button A triggers sound or flash
- button B changes color

---

# Not Included

- security or encryption
- internet play or NAT traversal
- compression
- reliable UDP
- delta updates
- rollback or prediction
- resumable asset downloads
- capability negotiation

---

# Summary

`picoplay` is a server-authoritative LAN game system with:

- `TCP` for control, assets, and input
- `UDP` for discovery and per-client realtime frame state delivery
- a Pico client that shows connection status, syncs assets, renders server-driven state, and reports local input
