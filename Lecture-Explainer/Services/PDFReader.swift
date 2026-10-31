//
//  PDFReader.swift
//  Lexia
//

import Foundation
import PDFKit
import UIKit

/// Reads a PDF on the device with Apple's PDFKit: page count, the text on each
/// page, and page thumbnails, for the file screen (its Pages and Text tabs).
///
/// Claude doesn't get this text: the PDF itself is sent (see PromptBuilder), so
/// scanned slides and equations drawn as images reach Claude too. PDFKit only finds
/// real text, which is why the Text tab can show less than Claude sees.
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

    /// Every page's text, each under a "[Page n]" marker.
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
