//
//  ModelTests.swift
//  Lecture-Explainer
//

import Testing
@testable import Lecture_Explainer
import Foundation
import SwiftData

// Checks the delete rules on the relationships. Each test gets its own
// in-memory store, so nothing is written to disk and tests don't affect each other.
@MainActor
struct ModelTests {
    // The container must be kept alive as a stored property: a context does not
    // keep its container alive, and using it after the container is freed crashes.
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(
            for: Project.self, Lecture.self, SourceMaterial.self, Explanation.self, ScheduleRule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func deletingProjectRemovesEverything() throws {
        let project = Project(name: "QM")
        context.insert(project)
        let lecture = Lecture(number: 1, date: .now)
        lecture.project = project
        let explanation = Explanation(markdown: "# L1")
        explanation.lecture = lecture
        let deck = SourceMaterial(fileName: "QM4Eng_L01.pdf", kind: .deck)
        deck.project = project
        let rule = ScheduleRule(weekday: 3, hour: 10, minute: 15, startDate: .now, endDate: .now)
        rule.project = project
        try context.save()

        context.delete(project)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Lecture>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Explanation>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SourceMaterial>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ScheduleRule>()) == 0)
    }

    @Test func deletingLectureKeepsItsDeck() throws {
        let project = Project(name: "QM")
        context.insert(project)
        let lecture = Lecture(number: 1, date: .now)
        lecture.project = project
        let deck = SourceMaterial(fileName: "QM4Eng_L01.pdf", kind: .deck)
        deck.project = project
        deck.lecture = lecture
        try context.save()

        context.delete(lecture)
        try context.save()

        // The file is unlinked, not deleted, and still belongs to the project.
        #expect(deck.lecture == nil)
        #expect(project.sources.count == 1)
    }
}
