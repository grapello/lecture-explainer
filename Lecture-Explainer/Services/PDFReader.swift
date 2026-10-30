//
//  PDFReader.swift
//  Lecture-Explainer
//

import Foundation
import PDFKit
import UIKit

/// Reads a PDF on the device with Apple's PDFKit: page count, the text on each
/// page, and page thumbnails.
///
/// Decision (roadmap open question): the app extracts text here instead of sending
/// the PDF itself to the API. That keeps requests small and cheap and lets you see
/// exactly what Claude will receive (the Text tab of a file). The trade-off: PDFKit
/// only finds real text. Equations drawn as images, diagrams and scanned pages give
/// little or no text, so check a deck's Text tab if an explanation seems to miss things.
struct PDFReader {
    private let document: PDFDocument

    /// nil if the file is missing or isn't a readable PDF.
    init?(url: URL) {
        guard let document = PDFDocument(url: url) else { return nil }
        self.document = document
    }

    var pageCount: Int { document.pageCount }

    /// The text PDFKit finds on one page (0-based index), trimmed. Empty for
    /// pages that are only images.
    func text(ofPage index: Int) -> String {
        (document.page(at: index)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every page's text, each under a "[Page n]" marker so Claude (and you) can
    /// refer to slides by number. This is what the prompt will contain in step 6.
    func fullText() -> String {
        (0..<pageCount).map { "[Page \($0 + 1)]\n\(text(ofPage: $0))" }
            .joined(separator: "\n\n")
    }

    /// A small image of one page, `width` points wide, keeping the page's proportions.
    func thumbnail(ofPage index: Int, width: CGFloat) -> UIImage? {
        guard let page = document.page(at: index) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let size = CGSize(width: width, height: width * bounds.height / max(bounds.width, 1))
        return page.thumbnail(of: size, for: .mediaBox)
    }
}
