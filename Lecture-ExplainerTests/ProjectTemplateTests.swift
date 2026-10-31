//
//  ProjectTemplateTests.swift
//  Lexia
//

import Testing
@testable import Lecture_Explainer
import Foundation
import SwiftData

/// "13.10.2026" as midnight local time, using the app's date formatter.
private func day(_ text: String) -> Date { formatter.date(from: text)! }

@MainActor
struct ProjectTemplateTests {
    let container: ModelContainer
    let old: Project

    init() throws {
        container = try TestSupport.makeContainer()
        old = Project(name: "QM WS26", instructions: "Derive every step.")
        container.mainContext.insert(old)
        // Tue 10:15 and Thu 14:00, 13 Oct to 2 Feb, with a holiday.
        for (weekday, hour) in [(3, 10), (5, 14)] {
            ScheduleRule(weekday: weekday, hour: hour, minute: weekday == 3 ? 15 : 0,
                         startDate: day("13.10.2026"), endDate: day("02.02.2027"),
                         skippedDates: [day("24.12.2026")]).project = old
        }
        Lecture(number: 1, date: day("13.10.2026")).project = old
    }

    @Test func copiesInstructionsAndWeeklyTimesButNotLectures() throws {
        let new = ProjectTemplate.makeProject(named: "QM SS27", instructions: old.instructions, from: old,
                                              startingOn: day("13.04.2027"), calendar: calendar)
        container.mainContext.insert(new)
        try container.mainContext.save()

        #expect(new.instructions == "Derive every step.")
        #expect(new.lectures.isEmpty)
        let slots = new.scheduleRules.map { "\($0.weekday) \($0.hour):\($0.minute)" }.sorted()
        #expect(slots == ["3 10:15", "5 14:0"])
        // Same length as the old semester (112 days), starting on the given day, no holidays.
        #expect(new.scheduleRules.allSatisfy { $0.startDate == day("13.04.2027") })
        #expect(new.scheduleRules.allSatisfy { $0.endDate == day("03.08.2027") })
        #expect(new.scheduleRules.allSatisfy { $0.skippedDates.isEmpty })
        #expect(old.scheduleRules.count == 2)   // the template itself is untouched
    }

    @Test func aTemplateWithoutScheduleGivesJustTheInstructions() {
        let bare = Project(name: "Notes", instructions: "Short.")
        let new = ProjectTemplate.makeProject(named: "Notes 2", instructions: bare.instructions, from: bare,
                                              startingOn: .now, calendar: calendar)
        #expect(new.scheduleRules.isEmpty)
        #expect(new.startDate == nil)
    }
}
