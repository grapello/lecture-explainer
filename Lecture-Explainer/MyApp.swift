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

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
