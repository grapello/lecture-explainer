//
//  SourceImporterTests.swift
//  Lecture-Explainer
//

import Testing
@testable import Lecture_Explainer
import Foundation
import SwiftData
import UIKit

/// Import, storage and PDF reading, with real PDF files in a temporary folder.
@MainActor
struct SourceImporterTests {
    let container: ModelContainer
    let project: Project
    let store: FileStore
    let inbox: URL   // stands in for the Files app: where picked files come from

    init() throws {
        container = try TestSupport.makeContainer()
        project = Project(name: "QM")
        container.mainContext.insert(project)
        for number in 1...3 {
            Lecture(number: number, date: .now).project = project
        }
        // Each test gets its own folders, so tests can't see each other's files.
        store = FileStore(baseURL: try TestSupport.makeTempFolder())
        inbox = try TestSupport.makeTempFolder()
    }

    func pdf(_ name: String) throws -> URL {
        try TestSupport.makePDF(named: name, pages: ["Page one"], in: inbox)
    }

    @Test func linksFilesByLectureNumberAndCopiesThem() throws {
        let outcome = SourceImporter.importFiles([try pdf("QM4Eng_L02_Intro.pdf")], into: project, store: store)
        let source = try #require(outcome.imported.first)
        #expect(source.kind == .deck)
        #expect(source.lecture?.number == 2)
        #expect(source.lecture?.status == .deckAdded)   // status follows automatically
        let copy = store.url(for: try #require(source.storedPath))
        #expect(FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)))
    }

    @Test func reportsFilesItCouldNotLink() throws {
        let outcome = SourceImporter.importFiles(
            [try pdf("Symbols_v1.pdf"), try pdf("Notes.pdf"), try pdf("QM4Eng_L09_Late.pdf")],
            into: project, store: store)
        // The symbols sheet is a reference (project-wide), so it doesn't count as unlinked.
        // Notes.pdf has no number; lecture 9 doesn't exist yet.
        #expect(outcome.unassigned.map(\.fileName) == ["Notes.pdf", "QM4Eng_L09_Late.pdf"])
        #expect(outcome.failed.isEmpty)
    }

    @Test func importingTheSameNameAgainUpdatesInsteadOfDuplicating() throws {
        let url = try pdf("QM4Eng_L01_Intro.pdf")
        SourceImporter.importFiles([url], into: project, store: store)
        SourceImporter.importFiles([url], into: project, store: store)
        #expect(project.sources.count == 1)
    }

    @Test func missingFileIsReportedNotCrashed() {
        let missing = inbox.appending(path: "QM4Eng_L01_Gone.pdf")
        let outcome = SourceImporter.importFiles([missing], into: project, store: store)
        #expect(outcome.imported.isEmpty)
        #expect(outcome.failed.map(\.fileName) == ["QM4Eng_L01_Gone.pdf"])
    }

    @Test func removingDeletesTheCopyAndTheRecord() throws {
        let source = try #require(SourceImporter.importFiles([try pdf("QM4Eng_L01.pdf")], into: project, store: store).imported.first)
        let copy = store.url(for: try #require(source.storedPath))
        SourceImporter.remove(source, context: container.mainContext, store: store)
        try container.mainContext.save()
        #expect(!FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)))
        #expect(project.sources.isEmpty)
    }

    @Test func removeFolderDeletesAllOfAProjectsFiles() throws {
        SourceImporter.importFiles([try pdf("QM4Eng_L01.pdf"), try pdf("QM4Eng_L02.pdf")], into: project, store: store)
        let folder = store.baseURL.appending(path: project.folderName)
        store.removeFolder(project.folderName)
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }
}

struct PDFReaderTests {
    @Test func readsPagesTextAndThumbnails() throws {
        let url = try TestSupport.makePDF(named: "deck.pdf", pages: ["Wave function", "Schrodinger equation"],
                                          in: try TestSupport.makeTempFolder())
        let reader = try #require(PDFReader(url: url))
        #expect(reader.pageCount == 2)
        #expect(reader.text(ofPage: 0).contains("Wave function"))
        #expect(reader.fullText().contains("[Page 2]\nSchrodinger equation"))
        let thumbnail = try #require(reader.thumbnail(ofPage: 0, width: 100))
        #expect(abs(thumbnail.size.width - 100) < 1)
    }

    @Test func notAPDFGivesNil() throws {
        let url = try TestSupport.makeTempFolder().appending(path: "fake.pdf")
        try Data("hello".utf8).write(to: url)
        #expect(PDFReader(url: url) == nil)
    }
}
