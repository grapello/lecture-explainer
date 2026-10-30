//
//  TestSupport.swift
//  Lecture-Explainer
//

import Foundation
import SwiftData
import UIKit
@testable import Lecture_Explainer

/// Helpers shared by several test files.
enum TestSupport {
    /// A fresh in-memory SwiftData store. Keep the returned container alive as
    /// long as you use its context (see ModelTests for why).
    @MainActor static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Project.self, Lecture.self, SourceMaterial.self, Explanation.self, ScheduleRule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// A new empty folder under the system's temporary directory.
    static func makeTempFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Writes a real PDF with one page per string, so PDFKit has text to find.
    /// Generated on the fly because course PDFs stay out of the repo (.gitignore).
    static func makePDF(named name: String, pages: [String], in folder: URL) throws -> URL {
        let url = folder.appending(path: name)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.writePDF(to: url) { context in
            for text in pages {
                context.beginPage()
                (text as NSString).draw(at: CGPoint(x: 72, y: 72),
                                        withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
            }
        }
        return url
    }
}
