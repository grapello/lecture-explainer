//
//  ExplainTests.swift
//  Lecture-Explainer
//

import Testing
@testable import Lecture_Explainer
import Foundation
import SwiftData

// Uses the Europe/Berlin calendar `cal` from WeekCalendarTests.swift.

struct PromptBuilderTests {
    let date = cal.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 10, minute: 15))!
    typealias Document = PromptBuilder.Document

    @Test func assemblesInstructionsFilesAndTask() {
        let prompt = PromptBuilder.build(
            courseName: "QM", instructions: "  Derive every step.  ",
            lectureNumber: 5, lectureTitle: "Spin", lectureDate: date,
            references: [Document(name: "Symbols.pdf", text: "ħ reduced Planck constant")],
            decks: [Document(name: "QM_L05.pdf", text: "[Page 1]\nSpin ½")],
            notes: [], timeZone: cal.timeZone)

        #expect(prompt.system.hasPrefix(PromptBuilder.baseSystem))
        #expect(prompt.system.hasSuffix("Instructions for this course:\nDerive every step."))
        #expect(prompt.user.hasPrefix("Course: QM\nLecture 5: Spin (Tuesday, October 27, 2026)"))
        #expect(prompt.user.contains("<reference name=\"Symbols.pdf\">\nħ reduced Planck constant\n</reference>"))
        #expect(prompt.user.contains("<deck name=\"QM_L05.pdf\">\n[Page 1]\nSpin ½\n</deck>"))
        #expect(prompt.user.hasSuffix("Explain lecture 5 using the slide deck above. Use the reference material for notation."))
        #expect(prompt.emptyFiles.isEmpty)
        // The Claude app gets everything in one text.
        #expect(prompt.combined == prompt.system + "\n\n---\n\n" + prompt.user)
    }

    @Test func leavesOutEmptyPartsAndFlagsFilesWithoutText() {
        let prompt = PromptBuilder.build(
            courseName: "", instructions: "", lectureNumber: 2, lectureTitle: "", lectureDate: date,
            references: [], decks: [Document(name: "Scan.pdf", text: "")],
            notes: [Document(name: "Deriv_L02_S4.pdf", text: "[Page 1]\nStep")], timeZone: cal.timeZone)

        #expect(prompt.system == PromptBuilder.baseSystem)
        #expect(prompt.user.hasPrefix("Lecture 2 (Tuesday"))
        #expect(prompt.user.contains("(No text could be extracted"))
        #expect(prompt.user.contains("and the derivation notes"))
        #expect(prompt.emptyFiles == ["Scan.pdf"])
    }

    @MainActor @Test func readsTheLecturesFilesFromStorage() throws {
        let container = try TestSupport.makeContainer()
        let project = Project(name: "QM")
        container.mainContext.insert(project)
        let lecture = Lecture(number: 1, date: date)
        lecture.project = project
        let store = FileStore(baseURL: try TestSupport.makeTempFolder())
        let inbox = try TestSupport.makeTempFolder()
        let urls = [try TestSupport.makePDF(named: "QM_L01.pdf", pages: ["Wave function"], in: inbox),
                    try TestSupport.makePDF(named: "Symbols.pdf", pages: ["psi"], in: inbox)]
        SourceImporter.importFiles(urls, into: project, store: store)

        let prompt = PromptBuilder.build(for: lecture, store: store)
        #expect(prompt.user.contains("<deck name=\"QM_L01.pdf\">\n[Page 1]\nWave function"))
        #expect(prompt.user.contains("<reference name=\"Symbols.pdf\">\n[Page 1]\npsi"))
    }
}

struct MarkdownParserTests {
    @Test func splitsIntoBlocks() {
        let blocks = MarkdownParser.parse("""
        ## Page 1

        First line
        second line

        - a
          more a
        - b
            - nested
        1. one
        2) two

        | x | y |
        |---|:-:|
        | 1 | 2 |
        | 3 |

        > quoted

        ```
        let a = 1
        ```
        ---
        """)
        #expect(blocks == [
            .heading(level: 2, text: "Page 1"),
            .paragraph("First line\nsecond line"),
            .list([.init(level: 0, number: nil, text: "a\nmore a"),
                   .init(level: 0, number: nil, text: "b"),
                   .init(level: 2, number: nil, text: "nested"),
                   .init(level: 0, number: "1.", text: "one"),
                   .init(level: 0, number: "2.", text: "two")]),
            .table(header: ["x", "y"], rows: [["1", "2"], ["3"]]),
            .quote("quoted"),
            .code("let a = 1"),
            .rule,
        ])
    }

    @Test func boldTextAndPipesInProseStayParagraphs() {
        // "**Note**" is not a list item, and a "|" line without a |---| row is not a table.
        #expect(MarkdownParser.parse("**Note** this\n|ψ|² is a density") == [
            .paragraph("**Note** this\n|ψ|² is a density"),
        ])
    }

    @Test func unfinishedCodeBlockWhileStreaming() {
        // Mid-stream the closing fence hasn't arrived yet; the code so far still shows.
        #expect(MarkdownParser.parse("```\nE = ħω") == [.code("E = ħω")])
    }
}

@MainActor
struct ExplainerTests {
    let container: ModelContainer
    let lectures: [Lecture]

    init() throws {
        container = try TestSupport.makeContainer()
        let project = Project(name: "QM")
        container.mainContext.insert(project)
        lectures = (1...2).map { number in
            let lecture = Lecture(number: number, date: .now)
            lecture.project = project
            // A deck without a stored file has no text; the stub below makes up for that.
            let deck = SourceMaterial(fileName: "L0\(number).pdf", kind: .deck)
            deck.project = project
            deck.lecture = lecture
            return lecture
        }
    }

    /// A fake answer in pieces, like the API would stream it.
    static func answer(_ pieces: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for piece in pieces { continuation.yield(piece) }
            continuation.finish()
        }
    }

    @Test func lectureWithoutReadableTextIsNotSent() async {
        let explainer = Explainer()
        var sent = 0
        explainer.send = { _ in sent += 1; return Self.answer(["x"]) }
        explainer.explain(lectures, context: container.mainContext)
        await explainer.waitUntilFinished()
        #expect(sent == 0)
        #expect(explainer.failure?.lecture == lectures[0])
        #expect(lectures[0].explanations.isEmpty)
    }

    @Test func savesEachAnswerAndStopsAtTheFirstError() async throws {
        // Give the lectures real text by importing real PDFs.
        let store = FileStore.shared
        let inbox = try TestSupport.makeTempFolder()
        for lecture in lectures {
            let url = try TestSupport.makePDF(named: "L0\(lecture.number).pdf", pages: ["Slide"], in: inbox)
            lecture.sources[0].storedPath = try store.copyIn(url, projectFolder: lecture.project!.folderName)
        }
        defer { store.removeFolder(lectures[0].project!.folderName) }

        let explainer = Explainer()
        var requests: [ClaudeRequest] = []
        explainer.send = { request in
            requests.append(request)
            if requests.count == 1 { return Self.answer(["## Page 1\n", "Hello"]) }
            throw ClaudeError.billing("Your credit balance is too low")
        }
        explainer.explain(lectures, context: container.mainContext)
        await explainer.waitUntilFinished()

        #expect(requests.count == 2)
        #expect(requests[0].userText.contains("Explain lecture 1"))
        #expect(lectures[0].explanations.map(\.markdown) == ["## Page 1\nHello"])
        #expect(lectures[0].explanations.first?.title == "Lecture 1")
        #expect(lectures[1].explanations.isEmpty)
        #expect(explainer.failure?.lecture == lectures[1])
        #expect(explainer.finished == 1)
        #expect(!explainer.isRunning)
    }
}
