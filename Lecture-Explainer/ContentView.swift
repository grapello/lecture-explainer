import SwiftUI
import SwiftData
import Playgrounds

struct ContentView: View {
    var body: some View {
        ProjectListView()
    }
}

#Preview {
    ContentView()
        .modelContainer(SampleData.makeContainer())
        .environment(Explainer())
}

#Playground {
    _ = 1 + 2
}
