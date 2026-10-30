import SwiftUI
import SwiftData

@main
struct MyApp: App {
    // The store the whole app shares. Made here (rather than with
    // `.modelContainer(for:)`) so a debug build can swap in sample data.
    let container: ModelContainer = {
        #if DEBUG
        // Xcode: Product > Scheme > Edit Scheme > Run > Arguments, add `--sample-data`.
        if CommandLine.arguments.contains("--sample-data") {
            return SampleData.makeContainer()
        }
        #endif
        return try! ModelContainer(for: Project.self, Lecture.self, SourceMaterial.self,
                                   Explanation.self, ScheduleRule.self)
    }()

    // One Explainer for the whole app, so a running explanation keeps going (and
    // stays visible) when you move between screens. See Explainer.swift.
    @State private var explainer = Explainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(explainer)
        }
        .modelContainer(container)
    }
}
