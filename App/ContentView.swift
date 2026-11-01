import SignalK
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.source == nil {
                ContentUnavailableView {
                    Label("No data source", systemImage: "sailboat")
                } description: {
                    Text("Connect to a Signal K server, or play the sample data.")
                } actions: {
                    Button("Choose Data Source…") { model.showsSourceSheet = true }
                        .buttonStyle(.borderedProminent)
                    Button("Play Sample Data") { model.start(.sample) }
                }
            } else {
                DashboardView()
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .sheet(isPresented: $model.showsSourceSheet) {
            SourceSheet()
                .appAppearance()
        }
    }
}

/// Connection state, in the top-left corner of the compass. Red or orange means the numbers on screen may be old.
struct StatusView: View {
    let source: DataSourceChoice
    let status: SourceStatus?
    @Environment(\.isNightVision) private var isNightVision

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(source.title).fontWeight(.medium)
            Text(detail).foregroundStyle(.secondary)
        }
        .font(.callout)
        .help(detail)
    }

    private var color: Color {
        switch status {
        // In night vision green turns black, so "connected" uses a dim dot and problems a bright one.
        case .connected: isNightVision ? .secondary : .green
        case .connecting, nil: .orange
        case .disconnected, .failed: .red
        }
    }

    private var detail: String {
        switch status {
        case .connected: "Connected"
        case .connecting, nil: "Connecting…"
        case .disconnected(let reason, let retryIn): "\(reason). Retry in \(retryIn) s"
        case .failed(let reason): reason
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
