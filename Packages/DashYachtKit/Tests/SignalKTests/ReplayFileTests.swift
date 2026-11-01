import Foundation
import Testing
import SignalK

struct ReplayFileTests {
    private func line(_ time: String) -> String {
        #"{"updates":[{"timestamp":"\#(time)","values":[{"path":"a","value":1}]}]}"#
    }

    @Test("Replay keeps the original timing between deltas")
    func timing() {
        let text = [line("2024-01-01T10:00:00Z"), line("2024-01-01T10:00:01.5Z"), line("2024-01-01T10:00:04Z")]
            .joined(separator: "\n")
        let file = ReplayFile(data: Data(text.utf8))
        #expect(file.entries.map(\.offset) == [.zero, .milliseconds(1500), .seconds(4)])
    }

    @Test("A timestamp that goes backwards does not move the replay back in time")
    func backwardsTimestamp() {
        let text = [line("2024-01-01T10:00:05Z"), line("2024-01-01T10:00:02Z"), line("2024-01-01T10:00:06Z")]
            .joined(separator: "\n")
        let file = ReplayFile(data: Data(text.utf8))
        #expect(file.entries.map(\.offset) == [.zero, .zero, .seconds(1)])
    }

    @Test("Broken lines are skipped and counted")
    func brokenLines() {
        let text = [line("2024-01-01T10:00:00Z"), "garbage", "", line("2024-01-01T10:00:01Z")].joined(separator: "\n")
        let file = ReplayFile(data: Data(text.utf8))
        #expect(file.entries.count == 2)
        #expect(file.skippedLines == 1)
    }

    @Test("A hello line gives the own vessel, so its AIS transponder is not a target")
    func helloLine() {
        let hello = #"{"name":"replay","version":"1","self":"vessels.urn:mrn:imo:mmsi:230035780"}"#
        let file = ReplayFile(data: Data([hello, line("2024-01-01T10:00:00Z")].joined(separator: "\n").utf8))
        #expect(file.selfContext == "vessels.urn:mrn:imo:mmsi:230035780")
        #expect(file.entries.count == 1)
        #expect(file.skippedLines == 0)
    }

    @Test("The sample file shipped with the app is a valid replay")
    func bundledSample() throws {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().appending(path: "../../../../App/SampleData/aava-n2k-3min.jsonl")
        let file = ReplayFile(data: try Data(contentsOf: url))
        #expect(file.skippedLines == 0)
        #expect(file.entries.count > 4000)
        #expect(file.entries.last?.offset ?? .zero > .seconds(170))
    }
}
