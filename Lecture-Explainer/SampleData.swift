//
//  SampleData.swift
//  Lecture-Explainer
//

// Everything in this file is wrapped in #if DEBUG, so it is left out of release builds.
#if DEBUG
import Foundation
import SwiftData

/// An in-memory store filled with example courses. Used by the #Preview blocks, and
/// by the app itself when launched with the `--sample-data` argument (handy until
/// the schedule and import screens exist and real data can be entered).
enum SampleData {
    @MainActor static func makeContainer() -> ModelContainer {
        // isStoredInMemoryOnly: nothing is written to disk, so previews start fresh every time.
        let container = try! ModelContainer(
            for: Project.self, Lecture.self, SourceMaterial.self, Explanation.self, ScheduleRule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext

        let qm = Project(name: "Quantum Mechanics for Engineers",
                         instructions: "Explain each slide for an engineering student. Derive every equation step by step and say what each symbol means.")
        context.insert(qm)
        context.insert(Project(name: "Signals and Systems"))

        // Tuesday and Thursday lectures, starting three weeks ago, so the list
        // has past, current and future weeks whatever day you open it.
        let start = calendar.date(byAdding: .weekOfYear, value: -3, to: mondayOfWeek(for: .now, in: calendar))!
        let end = calendar.date(byAdding: .weekOfYear, value: 6, to: start)!
        let tuesday = ScheduleRule(weekday: 3, hour: 10, minute: 15, startDate: start, endDate: end)
        let thursday = ScheduleRule(weekday: 5, hour: 14, minute: 0, startDate: start, endDate: end)
        // Setting the relationship to an object that is already in the context
        // inserts the new object too, so no separate insert call is needed.
        tuesday.project = qm
        thursday.project = qm

        for (index, date) in ScheduleGenerator.dates(for: [tuesday, thursday], calendar: calendar).enumerated() {
            let number = index + 1
            let lecture = Lecture(number: number, date: date)
            lecture.project = qm
            // The first three are explained, the next two have a deck, the rest have nothing yet.
            if number <= 5 {
                let deck = SourceMaterial(fileName: String(format: "QM4Eng_L%02d_Slides.pdf", number), kind: .deck)
                deck.project = qm
                deck.lecture = lecture
                lecture.status = .deckAdded
            }
            if number <= 3 {
                let explanation = Explanation(markdown: "# Lecture \(number)\n\nExample explanation text.",
                                              title: "Lecture \(number)")
                explanation.lecture = lecture
                lecture.status = .explained
            }
        }
        let symbols = SourceMaterial(fileName: "Symbols_v1.pdf", kind: .reference)
        symbols.project = qm

        return container
    }
}
#endif
