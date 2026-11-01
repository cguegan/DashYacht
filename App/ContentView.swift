import SwiftUI

struct ContentView: View {
    var body: some View {
        ContentUnavailableView("No data source", systemImage: "sailboat",
                               description: Text("Connect to a Signal K server or an NMEA gateway."))
            .frame(minWidth: 480, minHeight: 320)
    }
}

#Preview {
    ContentView()
}
