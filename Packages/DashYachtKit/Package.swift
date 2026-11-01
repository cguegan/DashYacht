// swift-tools-version: 6.0
import PackageDescription

// Platform-neutral modules. They must not import AppKit or UIKit (see CONTRIBUTING.md).
let package = Package(
    name: "DashYachtKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "NMEA0183", targets: ["NMEA0183"]),
        .library(name: "NMEA2000", targets: ["NMEA2000"]),
        .library(name: "SignalK", targets: ["SignalK"]),
        .library(name: "BoatData", targets: ["BoatData"]),
    ],
    targets: [
        .target(name: "NMEA0183"),
        .target(name: "NMEA2000"),
        .target(name: "SignalK"),
        .target(name: "BoatData", dependencies: ["SignalK"]),
        .testTarget(name: "NMEA0183Tests", dependencies: ["NMEA0183"]),
        .testTarget(name: "SignalKTests", dependencies: ["SignalK"]),
        .testTarget(name: "BoatDataTests", dependencies: ["BoatData"], resources: [.copy("Resources")]),
    ]
)
