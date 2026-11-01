# DashYacht – Project Plan

Native, open source macOS app that displays boat data from NMEA 0183 and NMEA 2000 in a clean, readable way.

## 1. What OpenPlotter teaches us

Source: OpenPlotter v4 docs and repositories, downloaded to `reference/openplotter/`.

- OpenPlotter is **not a library**. It is a Raspberry Pi OS (Debian) distribution plus a set of Python/wxPython "apps" that configure other software. It cannot run on macOS. We use it as a reference and as a **data source on the boat**.
- The centre of OpenPlotter is the **Signal K server** (Node.js). All inputs are converted to Signal K:
  - NMEA 0183 from serial / USB / TCP / UDP → Signal K. The raw multiplexed NMEA 0183 is also re-published on `tcp://openplotter.local:10110`.
  - NMEA 2000 from CAN adapters → decoded by **canboatjs** → Signal K. Supported adapters: Actisense NGT-1 (USB), `slcand` USB adapters (CANable), MCP2515 / MCP251xFD HATs (SocketCAN `can0`).
  - Seatalk 1 from GPIO → Signal K.
- Signal K outputs that a client can use:
  - WebSocket delta stream: `ws://openplotter.local:3000/signalk/v1/stream`
  - TCP delta stream: `tcp://openplotter.local:8375`
  - REST full model: `http://openplotter.local:3000/signalk/v1/api/`
- Existing dashboards in OpenPlotter are all web based (KIP, Grafana + InfluxDB, Node-RED dashboard, Ocearo UI). **No native Mac dashboard exists** – this is the gap DashYacht fills.

## 2. Key decision: where does the data come from?

| Source | Effort | Notes |
|---|---|---|
| **A. Signal K client** (WebSocket) | Low | Data is already decoded, normalised, in SI units, with source and timestamp. Works with OpenPlotter, any Signal K server, and several commercial gateways. Needs a Signal K server on board. |
| **B. NMEA 0183 direct** (TCP/UDP, e.g. port 10110, or USB serial) | Medium | Simple text protocol, ~30 common sentences to parse. Works with most Wi-Fi gateways without any server. |
| **C. NMEA 2000 direct** (gateway) | High | Need a PGN decoder (fast-packet reassembly, ~200 PGNs). Gateway formats differ: Yacht Devices YDWG-02/YDEN-02 RAW (TCP/UDP), Actisense NGT-1 binary (USB serial), `slcan` (CANable). Macs have no SocketCAN. |

**Recommendation:** build one internal data model (based on Signal K paths) and add sources in the order A → B → C. Source A gives a useful app in weeks; B and C make the app independent of a server later.

For NMEA 2000 decoding (C), do not write PGN definitions by hand: generate Swift code from the **canboat** `pgns.json` database (same source canboatjs uses). Check the canboat licence before including generated code.

## 3. Language and GUI

**Recommendation: Swift 6 + SwiftUI for everything. Do not use Rust for v1.**

Why:
- The work is mostly UI, networking and small parsers. Swift does all of this well; Rust gives no clear advantage here.
- A Rust core + Swift UI (via UniFFI) adds a second toolchain, a bridging layer, and a harder build/release for contributors. It is only worth it if you later want the same core on Linux / Raspberry Pi / Windows. We can keep the parser module free of UI code so this stays possible.
- Rust GUI toolkits (egui, iced, Slint, Tauri) do not look or feel native on macOS (menus, windows, full screen, dark mode, accessibility, keyboard). For a "beautiful native Mac app", SwiftUI is the best choice. I have no better GUI to suggest.

Swift building blocks (all Apple frameworks, no external dependency unless noted):
- UI: SwiftUI, `Canvas` for gauges/compass/wind rose, Swift Charts for history graphs.
- Network: `URLSessionWebSocketTask` (Signal K), `Network.framework` (`NWConnection`, `NWListener` for TCP/UDP), Bonjour/`NWBrowser` to discover Signal K servers (`_signalk-ws._tcp`).
- Serial (USB NMEA 0183, NGT-1): IOKit + POSIX `termios`, or the ORSSerialPort package.
- Storage: settings in `UserDefaults`/JSON; data history in SQLite (GRDB) or SwiftData – decide in phase 4.
- Tests: Swift Testing.

Tradeoffs to accept:
- macOS only (no Linux/Windows build).
- Minimum macOS version: suggest macOS 15 to use current SwiftUI and Observation APIs. Older Macs on board would be excluded.

## 4. Architecture

```
┌────────────── Sources ──────────────┐   ┌──── Core ────┐   ┌──── UI (SwiftUI) ────┐
│ SignalKSource (WebSocket)           │   │              │   │ Dashboard pages      │
│ NMEA0183Source (TCP / UDP / serial) │──▶│ DataStore    │──▶│ Widgets: digital,    │
│ NMEA2000Source (YDWG RAW / NGT-1)   │   │ (Signal K    │   │ gauge, compass, wind,│
│ ReplaySource (log files)            │   │  paths, SI)  │   │ graph, position, AIS │
└─────────────────────────────────────┘   └──────────────┘   └──────────────────────┘
```

Swift packages inside one Xcode project:
- `NMEA0183` – sentence parser (checksum, talker ID, ~30 sentences: RMC, GGA, GLL, VTG, HDG, HDT, HDM, MWV, MWD, VHW, VLW, DPT, DBT, MTW, XDR, RSA, RPM, ROT, XTE, RMB, APB, VDM/VDO (AIS), …). Pure Swift, no UI.
- `NMEA2000` – frame reader per gateway format, fast-packet reassembly, PGN decoder generated from canboat.
- `SignalK` – delta parser, client, server discovery.
- `BoatData` – the `DataStore`: one value per Signal K path + source + timestamp, staleness detection, unit conversion (SI → knots, °, m/ft, °C/°F, bar/psi).
- `DashYacht` app – windows, dashboard layout editor, widgets, settings.

Rules:
- All sources convert to Signal K paths (e.g. `navigation.speedOverGround`, `environment.wind.angleApparent`). The UI only knows paths, never sentences or PGNs.
- Values older than a timeout show as "stale" (greyed), never as live data. On a boat a frozen number is a safety risk.
- When two sources give the same path, use a configurable priority (like Signal K source priorities).
- UI refresh rate is limited (e.g. 4–10 Hz) independently of data rate, to save battery.

## 5. Phases

### Phase 0 – Setup (≈1 week)
- Git repository, MIT licence, README, CONTRIBUTING.
- Xcode project + Swift packages above, CI with GitHub Actions (build + tests).
- Test data: download Signal K sample delta files and canboat sample NMEA 2000 logs; record your own NMEA 0183 logs on board.
- **Done when:** empty app builds in CI, tests run.

### Phase 1 – Signal K client + first dashboard (≈3–4 weeks)
- Connect to a Signal K server (manual URL + Bonjour discovery), subscribe to deltas, reconnect automatically.
- `DataStore` with staleness and unit conversion.
- One fixed dashboard: SOG, COG, heading, depth, apparent/true wind, position, water temperature, battery voltage.
- Replay source for development without a boat.
- **Done when:** app shows live data from OpenPlotter on the boat and from a replay file, and greys out values when the feed stops.
- **Status (2026-11-01):** implemented. Tested: Signal K client against a local Signal K server (sample data), replay of the real NMEA 2000 sample through the data store, staleness, units. Not yet tested: OpenPlotter on the boat, automatic reconnection with a real server restart, Bonjour discovery on a real network.
- **Moved to phase 2:** limit the UI refresh rate; source priority when two devices send the same path (last value wins for now).

### Phase 2 – Beautiful widgets and layouts (≈4 weeks)
- Widgets: large digital value, analogue gauge, compass rose, wind instrument (apparent + true, close-hauled sectors), depth with alarm, history graph (Swift Charts), position/lat-lon.
- Editable dashboards: grid layout, add/remove/resize widgets, choose path and unit per widget, several pages.
- Day / dusk / **night mode (red)** for use at the helm at night. Full-screen mode. Large fonts readable from a distance.
- **Done when:** a user can build their own pages and the night mode does not destroy night vision.

### Phase 3 – NMEA 0183 direct (≈2–3 weeks)
- TCP client, UDP listener, USB serial; sentence parser; mapping to Signal K paths.
- AIS decoding (VDM/VDO) for a simple target list.
- **Done when:** the app works with a Wi-Fi NMEA 0183 gateway with no Signal K server.

### Phase 4 – Alarms and history (≈3 weeks)
- Alarms: depth, wind speed, anchor drag, battery low, stale data. Sound + macOS notification.
- Signal K notifications (`notifications.*`) displayed when connected to a server.
- Local history storage and longer graphs (24 h / 7 days).

### Phase 5 – NMEA 2000 direct (≈4–6 weeks)
- Gateway readers: Yacht Devices RAW (TCP/UDP) first (no driver, easy), then Actisense NGT-1 (USB serial binary) and W2K-1 (network).
- Fast-packet reassembly, generated PGN decoder, mapping to Signal K paths.
- Device list (PGN 60928 / 126996: name, manufacturer, model).
- **Done when:** app decodes the canboat sample logs correctly (tested) and a live bus through one gateway.

### Phase 6 – Release (≈2 weeks)
- App icon, signing with Developer ID, notarisation, DMG, Sparkle for updates (or Homebrew cask).
- User documentation (how to connect to OpenPlotter, to gateways).

Later ideas (not in scope now): iPad/iPhone version (SwiftUI makes this cheap), chart plotter view, write data back (autopilot control) – writing to the bus has safety impact and needs separate design.

## 6. Risks

- **NMEA 2000 specification is proprietary.** canboat is reverse-engineered; some PGNs will be incomplete. Mitigation: start with Signal K, which hides this.
- **USB serial drivers** for some gateways on Apple Silicon (NGT-1 uses FTDI – supported by macOS). Test real hardware early.
- **App Sandbox:** Mac App Store requires sandboxing; local network and serial access need entitlements. Direct distribution (notarised DMG) is simpler.
- **Safety:** this is a display tool, not certified navigation equipment. State it in the app and README.

## 7. Decisions (2026-11-01)

| Topic | Decision | Effect on the plan |
|---|---|---|
| Signal K server | None on board yet, one is planned | Keep Signal K first. Until it is on board, develop against a Signal K server running **on the Mac** (`npm install -g signalk-server`, it has built-in sample data) and the replay source. |
| Gateways | Yacht Devices and Actisense | Phase 5 order: Yacht Devices RAW (TCP/UDP) first, then Actisense (NGT-1 USB binary, W2K-1 over network). `slcan` dropped from scope. |
| Platforms | Mac now, iPad/iPhone later | Swift only, no Rust. Packages `NMEA0183`, `NMEA2000`, `SignalK`, `BoatData` must not import AppKit and must build for iOS. Serial/USB sources are macOS only (iOS has no USB serial); iOS will use network sources only. |
| Licence | MIT | Generated code from canboat must have a compatible licence – check in phase 5. |
| Minimum OS | macOS 15 (iOS 18 later) | Default kept, no objection given. |
