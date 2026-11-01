import SwiftUI

@main
struct DashYachtApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .appAppearance()
        }
        .commands {
            CommandGroup(after: .toolbar) {
                AppearancePicker()
            }
        }
    }
}
