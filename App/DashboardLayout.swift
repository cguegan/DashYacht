import BoatData
import Foundation
import Observation

/// The cards of each side panel. Saved at each change, so the dashboard is the same at the next launch.
@MainActor
@Observable
final class DashboardLayout {
    var left: [CardSettings] { didSet { save() } }
    var right: [CardSettings] { didSet { save() } }

    private static let key = "dashboard.layout"

    private struct Saved: Codable {
        var left: [CardSettings]
        var right: [CardSettings]
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            left = saved.left
            right = saved.right
        } else {
            left = [.speedOverGround, .speedThroughWater, .heading, .courseOverGround, .depth, .position]
                .map { CardSettings(instrument: $0) }
            right = [.apparentWindAngle, .apparentWindSpeed, .trueWindAngle, .trueWindSpeed, .waterTemperature, .batteryVoltage]
                .map { CardSettings(instrument: $0) }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Saved(left: left, right: right)) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
