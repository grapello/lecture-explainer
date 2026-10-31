//
//  ExplainTests.swift
//  Lexia
//

import Testing
@testable import Lecture_Explainer
import Foundation
import JavaScriptCore
import PDFKit
import SwiftData

// Uses the Europe/Berlin calendar `cal` from WeekCalendarTests.swift.

struct PromptBuilderTests {
    let date = cal.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 10, minute: 15))!

    @Test func describesTheAttachedPDFsAndTheTask() {
        let prompt = PromptBuilder.build(
            courseName: "QM", instructions: "  Derive every step.  ",
            lectureNumber: 5, lectureTitle: "Spin", lectureDate: date,
            references: ["Symbols.pdf"], decks: ["QM_L05.pdf"], notes: ["Deriv_L05_S4.pdf"],
            timeZone: cal.timeZone)

        #expect(prompt.system.hasPrefix(PromptBuilder.baseSystem))
        #expect(prompt.system.hasSuffix("Instructions for this course:\nDerive every step."))
        #expect(prompt.user == """
        Course: QM
        Lecture 5: Spin (Tuesday, October 27, 2026)

        Attached PDFs:
        - "Symbols.pdf": reference sheet for notation
        - "QM_L05.pdf": the lecture's slide deck
        - "Deriv_L05_S4.pdf": derivation notes that work out steps the slides only state

        Explain lecture 5 using the slide deck and the derivation notes. Use the reference sheet's notation.
        """)
        // The Claude app gets everything in one text.
        #expect(prompt.combined == prompt.system + "\n\n---\n\n" + prompt.user)
    }

    @Test func leavesOutEmptyParts() {
        let prompt = PromptBuilder.build(courseName: "", instructions: "", lectureNumber: 2, lectureTitle: "",
                                         lectureDate: date, references: [], decks: [], notes: [],
                                         timeZone: cal.timeZone)
        #expect(prompt.system == PromptBuilder.baseSystem)
        #expect(prompt.user == "Lecture 2 (Tuesday, October 27, 2026)\n\nExplain lecture 2 using the slide deck.")
    }

    @MainActor @Test func attachesStoredPDFsAndFlagsUnreadableOnes() throws {
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
        // A record whose file has gone missing.
        let lost = SourceMaterial(fileName: "QM_L01_S3_Deriv.pdf", kind: .notes)
        lost.project = project
        lost.lecture = lecture
        lost.storedPath = "\(project.folderName)/gone.pdf"

        let prompt = PromptBuilder.build(for: lecture, store: store)
        #expect(prompt.attachments.map(\.name) == ["Symbols.pdf", "QM_L01.pdf"])   // reference first
        #expect(prompt.attachments.map(\.kind) == [.reference, .deck])
        #expect(prompt.unreadable == ["QM_L01_S3_Deriv.pdf"])
        #expect(prompt.user.contains("- \"QM_L01.pdf\": the lecture's slide deck"))
        #expect(!prompt.user.contains("QM_L01_S3_Deriv.pdf"))
    }

    @Test func copyProtectedPDFsAreSentUnencrypted() throws {
        let folder = try TestSupport.makeTempFolder()
        let plain = try TestSupport.makePDF(named: "plain.pdf", pages: ["Slide"], in: folder)
        // Encrypted with an owner password only: opens without a password, like many course PDFs.
        let protected = folder.appending(path: "protected.pdf")
        let document = try #require(PDFDocument(url: plain))
        #expect(document.write(to: protected, withOptions: [.ownerPasswordOption: "owner"]))
        #expect(PDFDocument(url: protected)?.isEncrypted == true)

        let data = try PromptBuilder.data(for: .init(name: "protected.pdf", kind: .deck, url: protected))
        let copy = try #require(PDFDocument(data: data))
        #expect(!copy.isEncrypted)
        #expect(copy.pageCount == 1)
    }
}

@MainActor
struct ExplainerTests {
    let container: ModelContainer
    let lectures: [Lecture]
    let store = FileStore.shared

    init() throws {
        container = try TestSupport.makeContainer()
        let project = Project(name: "QM")
        container.mainContext.insert(project)
        lectures = (1...2).map { number in
            let lecture = Lecture(number: number, date: .now)
            lecture.project = project
            let deck = SourceMaterial(fileName: "L0\(number).pdf", kind: .deck)
            deck.project = project
            deck.lecture = lecture
            return lecture
        }
    }

    /// Gives each lecture's deck a real stored PDF (the Explainer reads from FileStore.shared).
    func storePDFs() throws {
        let inbox = try TestSupport.makeTempFolder()
        for lecture in lectures {
            let url = try TestSupport.makePDF(named: "L0\(lecture.number).pdf", pages: ["Slide"], in: inbox)
            lecture.sources[0].storedPath = try store.copyIn(url, projectFolder: lecture.project!.folderName)
        }
    }

    func cleanUp() { store.removeFolder(lectures[0].project!.folderName) }

    /// A fake answer in pieces, like the API would stream it.
    static func answer(_ pieces: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            for piece in pieces { continuation.yield(piece) }
            continuation.finish()
        }
    }

    @Test func lectureWithoutAFileIsNotSent() async {
        let explainer = Explainer()
        var sent = 0
        explainer.send = { _ in sent += 1; return Self.answer(["x"]) }
        explainer.explain(lectures, context: container.mainContext)
        await explainer.waitUntilFinished()
        #expect(sent == 0)
        #expect(explainer.failure?.lecture == lectures[0])
        #expect(explainer.failure?.message == ExplainerError.noFiles.localizedDescription)
    }

    @Test func sendsThePDFsSavesEachAnswerAndStopsAtTheFirstError() async throws {
        try storePDFs()
        defer { cleanUp() }
        let explainer = Explainer()
        var requests: [ClaudeRequest] = []
        explainer.send = { request in
            requests.append(request)
            if requests.count == 1 { return Self.answer(["## Page 1\n", "$\\psi$"]) }
            throw ClaudeError.billing("Your credit balance is too low")
        }
        explainer.explain(lectures, context: container.mainContext)
        await explainer.waitUntilFinished()

        #expect(requests.count == 2)
        #expect(requests[0].documents.map(\.title) == ["L01.pdf"])
        #expect(requests[0].documents[0].data.starts(with: Data("%PDF".utf8)))
        #expect(requests[0].userText.contains("Explain lecture 1"))
        #expect(lectures[0].explanations.map(\.markdown) == ["## Page 1\n$\\psi$"])
        #expect(lectures[1].explanations.isEmpty)
        #expect(explainer.failure?.lecture == lectures[1])
        #expect(explainer.finished == 1)
        #expect(!explainer.isRunning)
    }

    @Test func retriesWhenTheAPIIsBusy() async throws {
        try storePDFs()
        defer { cleanUp() }
        let explainer = Explainer()
        var attempts = 0
        var waits: [Duration] = []
        explainer.sleep = { waits.append($0) }
        explainer.send = { _ in
            attempts += 1
            switch attempts {
            case 1: throw ClaudeError.overloaded
            case 2: throw ClaudeError.rateLimited(retryAfter: 7)
            default: return Self.answer(["Done"])
            }
        }
        explainer.explain([lectures[0]], context: container.mainContext)
        await explainer.waitUntilFinished()

        #expect(attempts == 3)
        #expect(waits == [Explainer.retryDelays[0], .seconds(7)])   // the API's retry-after wins
        #expect(lectures[0].explanations.map(\.markdown) == ["Done"])
        #expect(explainer.failure == nil)
    }

    @Test func givesUpAfterTheLastRetry() async throws {
        try storePDFs()
        defer { cleanUp() }
        let explainer = Explainer()
        var attempts = 0
        explainer.sleep = { _ in }
        explainer.send = { _ in attempts += 1; throw ClaudeError.overloaded }
        explainer.explain([lectures[0]], context: container.mainContext)
        await explainer.waitUntilFinished()
        #expect(attempts == Explainer.retryDelays.count + 1)
        #expect(explainer.failure?.message == ClaudeError.overloaded.localizedDescription)
    }

    @Test(arguments: [true, false])
    func replacesOrKeepsTheOldExplanation(replacing: Bool) async throws {
        try storePDFs()
        defer { cleanUp() }
        Explanation(markdown: "Old", title: "Lecture 1").lecture = lectures[0]
        let explainer = Explainer()
        explainer.send = { _ in Self.answer(["New"]) }
        explainer.explain([lectures[0]], replacing: replacing, context: container.mainContext)
        await explainer.waitUntilFinished()
        let texts = lectures[0].explanations.filter { !$0.isDeleted }.map(\.markdown).sorted()
        #expect(texts == (replacing ? ["New"] : ["New", "Old"]))
    }
}

/// The formula renderer (lexia-render.js) run in JavaScriptCore: the same JavaScript
/// as in the app's web view, without the web view.
struct MathRendererTests {
    let context: JSContext

    init() throws {
        context = try #require(JSContext())
        for name in ["marked.min", "katex.min", "lexia-render"] {
            let url = try #require(Bundle.main.url(forResource: name, withExtension: "js"))
            context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        }
    }

    func render(_ markdown: String) -> String {
        context.objectForKeyedSubscript("lexiaRender").call(withArguments: [markdown]).toString()
    }

    @Test func typesetsInlineAndDisplayMaths() {
        let html = render("The state $\\psi_1$ obeys\n\n$$i\\hbar \\frac{\\partial \\psi}{\\partial t} = \\hat H \\psi$$")
        #expect(html.contains("class=\"katex\""))
        #expect(html.contains("katex-display"))
        #expect(html.contains("<mfrac>"))          // KaTeX's MathML for the fraction
        #expect(!html.contains("<em>"))            // the _ in psi_1 wasn't read as emphasis
    }

    @Test func rendersMarkdownAroundTheMaths() {
        let html = render("## Page 1\n\n| a | b |\n|---|---|\n| $x^2$ | **y** |\n\n- item")
        #expect(html.contains("<h2>Page 1</h2>"))
        #expect(html.contains("<table>"))
        #expect(html.contains("<strong>y</strong>"))
        #expect(html.contains("<li>item</li>"))
        #expect(html.contains("katex"))
    }

    @Test func leavesDollarsInCodeAndPricesAlone() {
        let html = render("`echo $HOME` costs $5 and $6")
        #expect(!html.contains("katex"))
        #expect(html.contains("<code>echo $HOME</code>"))
    }

    @Test func showsRawHTMLAsText() {
        let html = render("<script>alert(1)</script>")
        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;"))
    }
}
