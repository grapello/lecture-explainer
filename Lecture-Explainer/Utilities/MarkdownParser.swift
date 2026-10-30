//
//  MarkdownParser.swift
//  Lecture-Explainer
//

import Foundation

/// One block of a Markdown document: a heading, a paragraph, a table, …
///
/// SwiftUI's `Text` understands only *inline* Markdown (bold, italic, `code`, links),
/// not headings, lists or tables. So the explanation is first split into blocks
/// here, and MarkdownView draws each block with its own view, using Text's inline
/// Markdown for the text inside.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list([ListItem])
    case code(String)
    case table(header: [String], rows: [[String]])
    case quote(String)
    case rule

    struct ListItem: Equatable {
        /// Nesting depth, 0 for top level.
        var level: Int
        /// "1." for a numbered item, nil for a bullet.
        var number: String?
        var text: String
    }
}

/// Splits Markdown into blocks. Covers what Claude's explanations use; not a full
/// CommonMark parser (no nested quotes, no HTML, no reference links).
enum MarkdownParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var items: [MarkdownBlock.ListItem] = []
        var index = 0

        // A paragraph or list runs until something else starts; these close them.
        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        func flushList() {
            if !items.isEmpty { blocks.append(.list(items)) }
            items = []
        }
        func flush() { flushParagraph(); flushList() }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flush()
            } else if trimmed.hasPrefix("```") {
                // Code block: everything up to the closing fence, unchanged.
                flush()
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                blocks.append(.code(code.joined(separator: "\n")))
            } else if let match = trimmed.wholeMatch(of: /(#{1,6})\s+(.+)/) {
                flush()
                blocks.append(.heading(level: match.1.count, text: String(match.2)))
            } else if trimmed.wholeMatch(of: /(-\s*){3,}|(\*\s*){3,}|(_\s*){3,}/) != nil {
                flush()
                blocks.append(.rule)
            } else if trimmed.hasPrefix("|"), index + 1 < lines.count, isTableSeparator(lines[index + 1]) {
                // Table: a header row, a |---|---| row, then rows while lines start with "|".
                flush()
                let header = cells(trimmed)
                var rows: [[String]] = []
                index += 2
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(cells(lines[index].trimmingCharacters(in: .whitespaces)))
                    index += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            } else if trimmed.hasPrefix(">") {
                flush()
                var quote: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quote.append(String(lines[index].trimmingCharacters(in: .whitespaces).dropFirst())
                        .trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quote.joined(separator: "\n")))
                continue
            } else if let match = line.wholeMatch(of: /(\s*)([-*+]|\d+[.)])\s+(.*)/) {
                flushParagraph()
                let marker = String(match.2)
                let isNumber = marker.first?.isNumber == true
                // Two spaces of indent per level (four also work: they just count as two levels).
                items.append(.init(level: match.1.count / 2,
                                   number: isNumber ? marker.replacingOccurrences(of: ")", with: ".") : nil,
                                   text: String(match.3)))
            } else if !items.isEmpty, line.first?.isWhitespace == true {
                // An indented line under a list item continues that item.
                items[items.count - 1].text += "\n" + trimmed
            } else {
                flushList()
                paragraph.append(trimmed)
            }
            index += 1
        }
        flush()
        return blocks
    }

    /// "|---|:---:|" and the like.
    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.contains("-")
            && trimmed.allSatisfy { "|-: ".contains($0) }
    }

    /// "| a | b |" → ["a", "b"]
    private static func cells(_ row: String) -> [String] {
        var row = Substring(row)
        if row.hasPrefix("|") { row = row.dropFirst() }
        if row.hasSuffix("|") { row = row.dropLast() }
        return row.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
