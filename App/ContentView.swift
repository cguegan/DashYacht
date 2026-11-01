import SignalK
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var showSourceSheet = false

    var body: some View {
        Group {
            if model.source == nil {
                ContentUnavailableView {
                    Label("No data source", systemImage: "sailboat")
                } description: {
                    Text("Connect to a Signal K server, or play the sample data.")
                } actions: {
                    Button("Choose Data Source…") { showSourceSheet = true }
                        .buttonStyle(.borderedProminent)
                    Button("Play Sample Data") { model.start(.sample) }
                }
            } else {
                DashboardView()
            }
        }
        .frame(minWidth: 520, minHeight: 360)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let source = model.source {
                    StatusView(source: source, status: model.status)
                }
            }
            ToolbarItem {
                Button("Data Source", systemImage: "antenna.radiowaves.left.and.right") { showSourceSheet = true }
            }
        }
        .sheet(isPresented: $showSourceSheet) {
            SourceSheet()
        }
    }
}

/// Connection state in the toolbar. Red or orange means the numbers on screen may be old.
struct StatusView: View {
    let source: DataSourceChoice
    let status: SourceStatus?

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
        case .connected: .green
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
