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

    public private(set) var samples: [String: Sample] = [:]
    /// Context of the own vessel, from the server hello message.
    public private(set) var selfContext: String?

    public init() {}

    public func apply(_ message: Message, receivedAt: Date) {
        switch message {
        case .hello(let selfContext):
            self.selfContext = selfContext
        case .delta(let delta):
            guard isSelf(delta.context) else { return }
            for update in delta.updates {
                for item in update.values where !item.path.isEmpty {
                    samples[item.path] = Sample(value: item.value, sourceRef: update.sourceRef, receivedAt: receivedAt)
                }
            }
        }
    }

    /// Removes all values, for example when the user changes the data source.
    public func reset() {
        samples = [:]
        selfContext = nil
    }

    /// Returns the first of `paths` that has a live value. If none is live, returns the most
    /// recent stale one. Use this for alternatives, for example depth below keel or below transducer.
    ///
    /// A path can contain `*` for one segment, for example `electrical.batteries.*.voltage`.
    public func reading(_ paths: [String], now: Date, maxAge: TimeInterval = defaultMaxAge) -> Reading? {
        let readings = paths.flatMap(expand).compactMap { path -> Reading? in
            guard let sample = samples[path] else { return nil }
            let age = now.timeIntervalSince(sample.receivedAt)
            return Reading(path: path, sample: sample, freshness: age > maxAge ? .stale(age: age) : .live)
        }
        return readings.first(where: \.isLive) ?? readings.max { $0.sample.receivedAt < $1.sample.receivedAt }
    }

    public func reading(_ path: String, now: Date, maxAge: TimeInterval = defaultMaxAge) -> Reading? {
        reading([path], now: now, maxAge: maxAge)
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
