import BoatData
import Foundation
import Observation
import SignalK

/// Where the data comes from. Saved, so the app reconnects to the same source at launch.
enum DataSourceChoice: Equatable {
    case server(address: String)
    case replay(URL)
    case sample

    var title: String {
        switch self {
        case .server(let address): address
        case .replay(let url): url.lastPathComponent
        case .sample: "Sample data"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    let store = DataStore()
    let layout = DashboardLayout()
    private(set) var source: DataSourceChoice?
    private(set) var status: SourceStatus?
    private var task: Task<Void, Never>?

    static let sampleURL = Bundle.main.url(forResource: "aava-n2k-3min", withExtension: "jsonl")

    init() {
        if let saved = Self.loadSaved() { start(saved) }
    }

    func start(_ choice: DataSourceChoice) {
        task?.cancel()
        store.reset()
        source = choice
        save(choice)

        let events: AsyncStream<SourceEvent>
        switch choice {
        case .server(let address):
            guard let url = ServerAddress.streamURL(from: address) else {
                status = .failed(reason: "“\(address)” is not a valid server address")
                return
            }
            events = SignalKClient.events(url: url)
        case .replay(let url):
            events = ReplaySource.events(url: url)
        case .sample:
            guard let url = Self.sampleURL else {
                status = .failed(reason: "Sample data is missing from the app")
                return
            }
            events = ReplaySource.events(url: url)
        }

        task = Task { [store] in
            for await event in events {
                switch event {
                case .status(let status): self.status = status
                case .message(let message): store.apply(message, receivedAt: .now)
                }
            }
        }
    }

    // MARK: - Persistence

    private static let kindKey = "source.kind"
    private static let valueKey = "source.value"

    private func save(_ choice: DataSourceChoice) {
        let defaults = UserDefaults.standard
        switch choice {
        case .server(let address):
            defaults.set("server", forKey: Self.kindKey)
            defaults.set(address, forKey: Self.valueKey)
        case .replay(let url):
            defaults.set("replay", forKey: Self.kindKey)
            defaults.set(url.path(percentEncoded: false), forKey: Self.valueKey)
        case .sample:
            defaults.set("sample", forKey: Self.kindKey)
        }
    }

    private static func loadSaved() -> DataSourceChoice? {
        let defaults = UserDefaults.standard
        let value = defaults.string(forKey: valueKey)
        switch defaults.string(forKey: kindKey) {
        case "server": return value.map { .server(address: $0) }
        case "replay": return value.map { .replay(URL(filePath: $0)) }
        case "sample": return .sample
        default: return nil
        }
    }
}
