import Foundation
import Observation
import SignalK

/// The last value received for one Signal K path.
public struct Sample: Sendable, Equatable {
    public var value: JSONValue
    public var sourceRef: String?
    /// Local time of reception. Staleness uses this, not the timestamp in the data,
    /// because the clock of the boat network and the clock of the Mac can differ.
    public var receivedAt: Date
}

/// A value with its freshness, ready for display.
public struct Reading: Sendable, Equatable {
    public enum Freshness: Sendable, Equatable {
        case live
        /// No update for `age` seconds. The value is the last one received.
        case stale(age: TimeInterval)
    }

    public var path: String
    public var sample: Sample
    public var freshness: Freshness

    public var isLive: Bool { freshness == .live }
}

/// Values of the own vessel, keyed by Signal K path, in SI units.
@MainActor
@Observable
public final class DataStore {
    /// A value without update for longer than this is stale. Instruments on a boat
    /// normally send at 1 Hz or faster, so 5 s means something is wrong.
    public static let defaultMaxAge: TimeInterval = 5
    /// AIS class B sends a position only every 30 s (3 min when slow), so AIS targets age slower.
    public static let aisStaleAge: TimeInterval = 180
    /// AIS targets without a report for this time are no longer shown.
    public static let aisLostAge: TimeInterval = 600

    public private(set) var samples: [String: Sample] = [:]
    /// The last value of each source, by path and then by source reference ("" when the source is unknown).
    /// Used when the user picks one source for an instrument, for example one of two speed logs.
    public private(set) var samplesBySource: [String: [String: Sample]] = [:]
    /// Context of the own vessel, from the server hello message.
    public private(set) var selfContext: String?
    /// Values of other vessels (AIS), by context. Kept apart, so they never replace own values.
    public private(set) var otherVessels: [String: [String: Sample]] = [:]

    public init() {}

    public func apply(_ message: Message, receivedAt: Date) {
        switch message {
        case .hello(let selfContext):
            self.selfContext = selfContext
        case .delta(let delta):
            if isSelf(delta.context) {
                for update in delta.updates {
                    for item in update.values where !item.path.isEmpty {
                        let sample = Sample(value: item.value, sourceRef: update.sourceRef, receivedAt: receivedAt)
                        samples[item.path] = sample
                        samplesBySource[item.path, default: [:]][update.sourceRef ?? ""] = sample
                    }
                }
            } else if let context = delta.context, context.hasPrefix("vessels.") {
                var vessel = otherVessels[context] ?? [:]
                for update in delta.updates {
                    for item in update.values {
                        let sample = Sample(value: item.value, sourceRef: update.sourceRef, receivedAt: receivedAt)
                        if item.path.isEmpty {
                            // Static data such as the name comes as an object on the empty path.
                            if let name = item.value["name"] {
                                vessel["name"] = Sample(value: name, sourceRef: update.sourceRef, receivedAt: receivedAt)
                            }
                        } else {
                            vessel[item.path] = sample
                        }
                    }
                }
                otherVessels[context] = vessel
            }
        }
    }

    /// Removes all values, for example when the user changes the data source.
    public func reset() {
        samples = [:]
        samplesBySource = [:]
        selfContext = nil
        otherVessels = [:]
    }

    /// Returns the first of `paths` that has a live value. If none is live, returns the most
    /// recent stale one. Use this for alternatives, for example depth below keel or below transducer.
    ///
    /// A path can contain `*` for one segment, for example `electrical.batteries.*.voltage`.
    public func reading(_ paths: [String], now: Date, maxAge: TimeInterval = defaultMaxAge) -> Reading? {
        let readings = paths.flatMap(expand).compactMap { path in
            samples[path].map { Self.reading(path, $0, now: now, maxAge: maxAge) }
        }
        return readings.first(where: \.isLive) ?? readings.max { $0.sample.receivedAt < $1.sample.receivedAt }
    }

    public func reading(_ path: String, now: Date, maxAge: TimeInterval = defaultMaxAge) -> Reading? {
        reading([path], now: now, maxAge: maxAge)
    }

    /// The value of one source only, even when another source sends the same path.
    public func reading(_ selection: SourceSelection, now: Date, maxAge: TimeInterval = defaultMaxAge) -> Reading? {
        samplesBySource[selection.path]?[selection.sourceRef ?? ""]
            .map { Self.reading(selection.path, $0, now: now, maxAge: maxAge) }
    }

    /// Every path and source received for `paths` (wildcards expanded), for the user to choose from.
    public func sources(for paths: [String]) -> [SourceSelection] {
        paths.flatMap(expand).flatMap { path in
            (samplesBySource[path] ?? [:]).keys.sorted().map {
                SourceSelection(path: path, sourceRef: $0.isEmpty ? nil : $0)
            }
        }
    }

    private static func reading(_ path: String, _ sample: Sample, now: Date, maxAge: TimeInterval) -> Reading {
        let age = now.timeIntervalSince(sample.receivedAt)
        return Reading(path: path, sample: sample, freshness: age > maxAge ? .stale(age: age) : .live)
    }

    /// AIS targets with a position received less than `aisLostAge` ago.
    public func aisTargets(now: Date) -> [AISTarget] {
        otherVessels.compactMap { context, values -> AISTarget? in
            guard let position = values["navigation.position"],
                  let latitude = position.value["latitude"]?.number,
                  let longitude = position.value["longitude"]?.number else { return nil }
            let age = now.timeIntervalSince(position.receivedAt)
            guard age <= Self.aisLostAge else { return nil }
            return AISTarget(
                id: context,
                name: values["name"]?.value.string,
                position: Coordinate(latitude: latitude, longitude: longitude),
                speed: values["navigation.speedOverGround"]?.value.number,
                course: values["navigation.courseOverGroundTrue"]?.value.number,
                age: max(0, age)
            )
        }
        .sorted { $0.id < $1.id }
    }

    private func isSelf(_ context: String?) -> Bool {
        guard let context else { return true }
        return context == "vessels.self" || context == selfContext
    }

    private func expand(_ pattern: String) -> [String] {
        guard pattern.contains("*") else { return [pattern] }
        let parts = pattern.split(separator: ".", omittingEmptySubsequences: false)
        return samples.keys.filter { key in
            let keyParts = key.split(separator: ".", omittingEmptySubsequences: false)
            return keyParts.count == parts.count && zip(parts, keyParts).allSatisfy { $0 == "*" || $0 == $1 }
        }.sorted()
    }
}
