# DashYacht

A native, open source macOS app that displays boat data from NMEA 0183 and NMEA 2000.

> **Status:** early development (phase 1 of [PLAN.md](PLAN.md)). DashYacht connects to a Signal K server or plays a recorded file, and shows one fixed dashboard.

> **Safety:** DashYacht is a display tool. It is not certified navigation equipment. Do not use it as your only source of navigation data.

## Requirements

- macOS 15 or later
- Xcode 16 or later (to build)

## Data sources

| Source | Status |
|---|---|
| Signal K server (for example [OpenPlotter](https://openplotter.readthedocs.io/)) over WebSocket | Available |
| Replay file (one Signal K delta per line) and built-in sample data | Available |
| NMEA 0183 over TCP, UDP or USB serial | Planned (phase 3) |
| NMEA 2000 through Yacht Devices and Actisense gateways | Planned (phase 5) |

To connect, click the antenna button in the toolbar and type the server address, for example `openplotter.local` or `10.42.0.1:3000`. Servers on the local network that advertise themselves with Bonjour are listed automatically.

Values that stop updating for more than 5 seconds are greyed out and marked "Old".

## Build

Open `DashYacht.xcodeproj` in Xcode and run the `DashYacht` scheme.

From the command line:

```bash
swift test --package-path Packages/DashYachtKit
xcodebuild -project DashYacht.xcodeproj -scheme DashYacht -destination 'platform=macOS' build
```

### Test with a local Signal K server

You do not need a boat. The Signal K server can replay its NMEA 2000 sample data on your Mac:

```bash
npx signalk-server --sample-n2k-data
```

Then connect DashYacht to `localhost:3000`. To run the client test against this server:

```bash
SIGNALK_TEST_ADDRESS=localhost:3000 swift test --package-path Packages/DashYachtKit --filter LiveServer
```

## Project layout

| Folder | Content |
|---|---|
| `App/` | macOS app (SwiftUI) |
| `Packages/DashYachtKit/` | Platform-neutral Swift modules: `NMEA0183`, `NMEA2000`, `SignalK`, `BoatData` |

## Licence

[MIT](LICENSE)
