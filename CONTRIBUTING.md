# Contributing

Thank you for your interest in DashYacht.

## Before you start

- Read [PLAN.md](PLAN.md) to see the architecture and the current phase.
- For a large change, open an issue first so we can agree on the approach.

## Rules

- The modules in `Packages/DashYachtKit` must not import AppKit or UIKit. They must build for macOS and iOS.
- The UI uses Signal K paths only. It never reads NMEA sentences or PGNs directly.
- Old data must never look like live data. A value that stops updating must show as stale.
- Every parser change needs a test with a real sentence or frame. Tests use Swift Testing.

## Check your change

```bash
swift test --package-path Packages/DashYachtKit
xcodebuild -project DashYacht.xcodeproj -scheme DashYacht -destination 'platform=macOS' build
```

## Licence

By contributing, you agree that your contribution is licensed under the [MIT licence](LICENSE).
