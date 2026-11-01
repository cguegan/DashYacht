# DashYacht

A native, open source macOS app that displays boat data from NMEA 0183 and NMEA 2000.

> **Status:** early development. Nothing works yet. See [PLAN.md](PLAN.md).

> **Safety:** DashYacht is a display tool. It is not certified navigation equipment. Do not use it as your only source of navigation data.

## Requirements

- macOS 15 or later
- Xcode 16 or later (to build)

## Data sources (planned)

1. Signal K server (for example [OpenPlotter](https://openplotter.readthedocs.io/)) over WebSocket
2. NMEA 0183 over TCP, UDP or USB serial
3. NMEA 2000 through Yacht Devices and Actisense gateways

## Build

Open `DashYacht.xcodeproj` in Xcode and run the `DashYacht` scheme.

From the command line:

```bash
swift test --package-path Packages/DashYachtKit
xcodebuild -project DashYacht.xcodeproj -scheme DashYacht -destination 'platform=macOS' build
```

## Project layout

| Folder | Content |
|---|---|
| `App/` | macOS app (SwiftUI) |
| `Packages/DashYachtKit/` | Platform-neutral Swift modules: `NMEA0183`, `NMEA2000`, `SignalK`, `BoatData` |

## Licence

[MIT](LICENSE)
