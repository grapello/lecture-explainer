import SwiftUI
import SwiftData

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Project.self, Lecture.self, SourceMaterial.self,
                              Explanation.self, ScheduleRule.self])
    }
}
