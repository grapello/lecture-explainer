import SwiftUI
import SwiftData
import Playgrounds

/// The root view: the project list, with the Lexia loading screen on top for the
/// first moment after launch.
struct ContentView: View {
    @State private var showsSplash = true

    var body: some View {
        ZStack {
            ProjectListView()
            if showsSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)   // keeps the splash on top while it fades out
            }
        }
        .task {
            // Long enough to read the name, short enough not to be in the way.
            try? await Task.sleep(for: .seconds(1.3))
            withAnimation(.easeOut(duration: 0.45)) { showsSplash = false }
        }
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
