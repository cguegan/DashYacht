import Foundation

/// A recorded Signal K stream: one delta (JSON) per line.
public struct ReplayFile: Sendable {
    public struct Entry: Sendable, Equatable {
        /// Time since the first entry, from the delta timestamps.
        public var offset: Duration
        public var delta: Delta
    }

    public var entries: [Entry]
    /// Lines that are not valid deltas. They are skipped.
    public var skippedLines: Int

    public init(data: Data) {
        var entries: [Entry] = []
        var skipped = 0
        var start: Date?
        var last: Duration = .zero

        for line in data.split(separator: UInt8(ascii: "\n")) where !line.allSatisfy({ $0 == 32 || $0 == 13 }) {
            guard case .delta(let delta)? = Message.decode(Data(line)) else {
                skipped += 1
                continue
            }
            // Deltas without a timestamp play at the same time as the previous one.
            // Time never goes backwards, so a bad timestamp cannot stall the replay.
            if let timestamp = delta.updates.compactMap(\.timestamp).first {
                let begin = start ?? timestamp
                start = begin
                last = max(last, .seconds(timestamp.timeIntervalSince(begin)))
            }
            entries.append(Entry(offset: last, delta: delta))
        }
        self.entries = entries
        self.skippedLines = skipped
    }
}

/// Plays a `ReplayFile` in real time and loops at the end. Used for development and demos.
public enum ReplaySource {
    public static func events(url: URL) -> AsyncStream<SourceEvent> {
        AsyncStream { continuation in
            let task = Task {
                continuation.yield(.status(.connecting))
                let file: ReplayFile
                do {
                    file = ReplayFile(data: try Data(contentsOf: url))
                } catch {
                    continuation.yield(.status(.failed(reason: error.localizedDescription)))
                    continuation.finish()
                    return
                }
                guard !file.entries.isEmpty else {
                    continuation.yield(.status(.failed(reason: "No Signal K deltas in \(url.lastPathComponent)")))
                    continuation.finish()
                    return
                }
                continuation.yield(.status(.connected))

                let clock = ContinuousClock()
                while !Task.isCancelled {
                    let start = clock.now
                    for entry in file.entries {
                        try? await clock.sleep(until: start + entry.offset)
                        if Task.isCancelled { break }
                        continuation.yield(.message(.delta(entry.delta)))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
