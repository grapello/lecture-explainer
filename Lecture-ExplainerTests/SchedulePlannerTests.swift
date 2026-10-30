//
//  SchedulePlannerTests.swift
//  Lecture-Explainer
//

import Testing
@testable import Lecture_Explainer
import Foundation
import SwiftData

// Uses the Europe/Berlin calendar `cal` from WeekCalendarTests.swift.
@MainActor
struct SchedulePlannerTests {
    func date(_ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 15) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    typealias Existing = SchedulePlanner.Existing

    // MARK: - plan(): the pure logic

    @Test func addsDaysWithoutLecture() {
        let plan = SchedulePlanner.plan(existing: [Existing(date: date(10, 13), isManual: false, hasContent: false)],
                                        generated: [date(10, 13), date(10, 20)], calendar: cal)
        #expect(plan.datesToAdd == [date(10, 20)])
        #expect(plan.indicesToRemove.isEmpty)
    }

    @Test func removesOnlyUntouchedLecturesNoLongerScheduled() {
        // 20 Oct became a holiday: three lectures sit on it, only the untouched one goes.
        let existing = [
            Existing(date: date(10, 20), isManual: false, hasContent: false),  // generated, untouched
            Existing(date: date(10, 20), isManual: true, hasContent: false),   // added by hand
            Existing(date: date(10, 20), isManual: false, hasContent: true),   // has a deck
        ]
        let plan = SchedulePlanner.plan(existing: existing, generated: [date(10, 13)], calendar: cal)
        #expect(plan.indicesToRemove == [0])
    }

    @Test func movesGeneratedLecturesWhenTheSlotTimeChanges() {
        let existing = [Existing(date: date(10, 13, 10, 15), isManual: false, hasContent: false),
                        Existing(date: date(10, 20, 9, 0), isManual: true, hasContent: false)]
        let plan = SchedulePlanner.plan(existing: existing,
                                        generated: [date(10, 13, 12, 0), date(10, 20, 12, 0)], calendar: cal)
        #expect(plan.datesToMove == [0: date(10, 13, 12, 0)])   // the manual one keeps 9:00
        #expect(plan.datesToAdd.isEmpty)
    }

    // MARK: - apply(): against a real (in-memory) store

    @Test func applyCreatesNumberedLecturesAndRespectsLaterHolidays() throws {
        let container = try TestSupport.makeContainer()
        let context = container.mainContext
        let project = Project(name: "QM")
        context.insert(project)
        let rule = ScheduleRule(weekday: 3, hour: 10, minute: 15,
                                startDate: date(10, 13), endDate: date(11, 3))
        rule.project = project

        SchedulePlanner.apply(to: project, context: context, calendar: cal)
        try context.save()
        let numbers = project.lectures.sorted { $0.date < $1.date }.map(\.number)
        #expect(numbers == [1, 2, 3, 4])   // Tuesdays 13, 20, 27 Oct and 3 Nov

        // A deck is added to 27 Oct, then 20 and 27 Oct are both declared holidays.
        let lecture27 = project.lectures.first { cal.component(.day, from: $0.date) == 27 }!
        let deck = SourceMaterial(fileName: "L03.pdf", kind: .deck)
        deck.project = project
        deck.lecture = lecture27
        rule.skippedDates = [date(10, 20, 0, 0), date(10, 27, 0, 0)]

        SchedulePlanner.apply(to: project, context: context, calendar: cal)
        try context.save()
        let remaining = project.lectures.sorted { $0.date < $1.date }
        // 20 Oct is gone; 27 Oct stays because it has a deck, and keeps the deck's
        // number 3, so there is no lecture 2 and 3 Nov follows as lecture 4.
        #expect(remaining.map { cal.component(.day, from: $0.date) } == [13, 27, 3])
        #expect(remaining.map(\.number) == [1, 3, 4])
    }

    @Test func renumberFollowsAHandMovedLecture() throws {
        let container = try TestSupport.makeContainer()
        let project = Project(name: "QM")
        container.mainContext.insert(project)
        for (number, day) in [(1, 13), (2, 15), (3, 20)] {
            Lecture(number: number, date: date(10, day)).project = project
        }
        // Lecture 3 is moved before lecture 2.
        project.lectures.first { $0.number == 3 }!.date = date(10, 14)
        SchedulePlanner.renumber(project)
        let byDate = project.lectures.sorted { $0.date < $1.date }
        #expect(byDate.map { cal.component(.day, from: $0.date) } == [13, 14, 15])
        #expect(byDate.map(\.number) == [1, 2, 3])
    }

    // MARK: - numbers(pinned:): deck numbers win

    @Test(arguments: [
        ([nil, nil, nil], [1, 2, 3]),             // no decks: date order
        ([nil, nil, 7, nil], [1, 2, 7, 8]),       // a holiday left a gap before L07
        ([nil, 2, nil, nil], [1, 2, 3, 4]),       // deck matches the date order
        ([nil, nil, nil, 2], [1, 3, 4, 2]),       // deck L02 on a later date: 2 isn't reused
        ([5, nil], [5, 6]),                       // first lectures missing entirely
    ] as [([Int?], [Int])])
    func numbersKeepDeckNumbers(pinned: [Int?], expected: [Int]) {
        #expect(SchedulePlanner.numbers(pinned: pinned) == expected)
    }

    @Test func renumberKeepsTheDeckNumberAfterAHandAddedLecture() throws {
        let container = try TestSupport.makeContainer()
        let project = Project(name: "QM")
        container.mainContext.insert(project)
        for (number, day) in [(1, 13), (2, 20)] {
            Lecture(number: number, date: date(10, day)).project = project
        }
        let deck = SourceMaterial(fileName: "QM4Eng_L02_Spin.pdf", kind: .deck)
        deck.project = project
        deck.lecture = project.lectures.first { $0.number == 2 }
        // An extra lecture is added between them; it must not take the deck's number.
        Lecture(number: 0, date: date(10, 15), isManual: true).project = project
        SchedulePlanner.renumber(project)
        let byDate = project.lectures.sorted { $0.date < $1.date }
        #expect(byDate.map(\.number) == [1, 3, 2])
    }
}
