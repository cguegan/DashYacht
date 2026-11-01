import Foundation

/// Connects to a Signal K server stream and reconnects automatically.
public enum SignalKClient {
    /// Delays between reconnection attempts, in seconds. The last value repeats.
    static let retryDelays = [1, 2, 5, 10, 30]

    /// If the server sends nothing for this time, the connection is treated as dead.
    /// A real boat sends many messages per second, so silence means a problem.
    static let silenceTimeout: Duration = .seconds(15)

    /// Streams events until the consumer stops iterating.
    public static func events(url: URL, session: URLSession = .shared) -> AsyncStream<SourceEvent> {
        AsyncStream { continuation in
            let task = Task {
                var attempt = 0
                while !Task.isCancelled {
                    continuation.yield(.status(.connecting))
                    let reason = await runConnection(url: url, session: session, continuation: continuation) {
                        attempt = 0
                    }
                    if Task.isCancelled { break }
                    let delay = retryDelays[min(attempt, retryDelays.count - 1)]
                    attempt += 1
                    continuation.yield(.status(.disconnected(reason: reason, retryIn: delay)))
                    try? await Task.sleep(for: .seconds(delay))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Runs one connection until it fails. Returns the reason.
    private static func runConnection(
        url: URL,
        session: URLSession,
        continuation: AsyncStream<SourceEvent>.Continuation,
        onFirstMessage: () -> Void
    ) async -> String {
        let socket = session.webSocketTask(with: url)
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }

        let watchdog = Watchdog(timeout: silenceTimeout) { socket.cancel(with: .abnormalClosure, reason: nil) }
        defer { watchdog.stop() }

        var connected = false
        while !Task.isCancelled {
            let frame: URLSessionWebSocketTask.Message
            do {
                frame = try await socket.receive()
            } catch {
                return watchdog.fired ? "No data for \(silenceTimeout.components.seconds) s" : error.localizedDescription
            }
            watchdog.reset()
            if !connected {
                connected = true
                onFirstMessage()
                continuation.yield(.status(.connected))
            }
            let data: Data
            switch frame {
            case .string(let text): data = Data(text.utf8)
            case .data(let bytes): data = bytes
            @unknown default: continue
            }
            if let message = Message.decode(data) {
                continuation.yield(.message(message))
            }
        }
        return "Stopped"
    }
}

/// Calls `onTimeout` once when `reset()` is not called within `timeout`.
private final class Watchdog: @unchecked Sendable {
    private let lock = NSLock()
    private var lastReset = ContinuousClock.now
    private var _fired = false
    private var task: Task<Void, Never>?

    init(timeout: Duration, onTimeout: @escaping @Sendable () -> Void) {
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if self.checkExpired(timeout) {
                    onTimeout()
                    return
                }
            }
        }
    }

    var fired: Bool { lock.withLock { _fired } }

    func reset() { lock.withLock { lastReset = .now } }

    func stop() { task?.cancel() }

    private func checkExpired(_ timeout: Duration) -> Bool {
        lock.withLock {
            if ContinuousClock.now - lastReset > timeout { _fired = true }
            return _fired
        }
    }
}
