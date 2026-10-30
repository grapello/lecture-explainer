//
//  PromptBuilder.swift
//  Lecture-Explainer
//

import Foundation

/// What Claude reads for one lecture. The same prompt is used whether it goes
/// through the API (Explainer) or is handed to the Claude app by hand.
struct LecturePrompt: Equatable {
    /// How to answer: the app's fixed rules plus the project's instructions.
    var system: String
    /// The lecture's material and the task.
    var user: String
    /// Files that gave no text (scanned or image-only pages). Claude can't see
    /// those, so the screen warns about them.
    var emptyFiles: [String] = []

    /// Both parts in one text, for the Claude app, which has no separate field for
    /// a system prompt.
    var combined: String { "\(system)\n\n---\n\n\(user)" }
}

/// Turns a lecture and its files into a LecturePrompt.
///
/// Split in two: `build(for:)` reads the PDFs, and the static `build(...)` below
/// only assembles text. The second one needs no files or database, so tests can
/// check the exact prompt.
enum PromptBuilder {
    struct Document: Equatable {
        var name: String
        /// The extracted text ("[Page 1]\n…"), or "" if the file has none.
        var text: String
    }

    /// The fixed part of the system prompt. The project's own instructions are
    /// added after it, so they can refine or override the style.
    static let baseSystem = """
    You explain university lectures from their slide decks. The reader is a student \
    who wants to understand the lecture well enough to work with it: follow the deck \
    in order, refer to slides by their page number, explain what each slide says and \
    why, fill in steps the slides skip, and say what each symbol means when it first \
    appears.

    Format the answer as Markdown: a "## Page n" heading (or "## Pages n–m" for slides \
    that belong together) for each part, short paragraphs, lists and tables where \
    they help. Write mathematics in plain Unicode (ψ(x, t), ħ, ∂ψ/∂t, x², ∫, ∑, x₀), \
    never LaTeX: the app that shows your answer can't render LaTeX.
    """

    /// Reads the lecture's files (and the project's references) and builds its prompt.
    static func build(for lecture: Lecture, store: FileStore = .shared) -> LecturePrompt {
        let project = lecture.project
        func documents(_ sources: [SourceMaterial]) -> [Document] {
            // By slide first (notes for slide 4 before slide 22), then by name.
            sources.sorted { ($0.slide ?? 0, $0.fileName) < ($1.slide ?? 0, $1.fileName) }
                .map { Document(name: $0.fileName, text: text(of: $0, store: store)) }
        }
        return build(courseName: project?.name ?? "",
                     instructions: project?.instructions ?? "",
                     lectureNumber: lecture.number,
                     lectureTitle: lecture.title,
                     lectureDate: lecture.date,
                     references: documents((project?.sources ?? []).filter { $0.kind == .reference }),
                     decks: documents(lecture.sources.filter { $0.kind == .deck }),
                     notes: documents(lecture.sources.filter { $0.kind == .notes }))
    }

    /// The extracted text of one file, or "" if it is missing or has no text at all.
    private static func text(of source: SourceMaterial, store: FileStore) -> String {
        guard let path = source.storedPath, let reader = PDFReader(url: store.url(for: path)) else { return "" }
        let hasText = (0..<reader.pageCount).contains { !reader.text(ofPage: $0).isEmpty }
        return hasText ? reader.fullText() : ""
    }

    static func build(courseName: String, instructions: String,
                      lectureNumber: Int, lectureTitle: String, lectureDate: Date,
                      references: [Document], decks: [Document], notes: [Document],
                      timeZone: TimeZone = calendar.timeZone) -> LecturePrompt {
        var system = baseSystem
        let instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty {
            system += "\n\nInstructions for this course:\n\(instructions)"
        }

        // A fixed English date format, so the prompt doesn't change with the phone's language.
        var dateStyle = Date.FormatStyle(date: .complete, time: .omitted, locale: Locale(identifier: "en_US"))
        dateStyle.timeZone = timeZone
        var heading = "Lecture \(lectureNumber)"
        if !lectureTitle.isEmpty { heading += ": \(lectureTitle)" }
        heading += " (\(lectureDate.formatted(dateStyle)))"
        if !courseName.isEmpty { heading = "Course: \(courseName)\n\(heading)" }

        // Each file in its own tag, so Claude can tell where one ends and which
        // kind it is. Tags like these are the usual way to mark up documents in a prompt.
        var emptyFiles: [String] = []
        func section(_ tag: String, _ document: Document) -> String {
            var text = document.text
            if text.isEmpty {
                emptyFiles.append(document.name)
                text = "(No text could be extracted from this file; its pages are probably images.)"
            }
            return "<\(tag) name=\"\(document.name)\">\n\(text)\n</\(tag)>"
        }
        var parts = [heading]
        parts += references.map { section("reference", $0) }
        parts += decks.map { section("deck", $0) }
        parts += notes.map { section("notes", $0) }

        var task = "Explain lecture \(lectureNumber) using the slide deck above"
        if !notes.isEmpty { task += " and the derivation notes, which work out steps the slides only state" }
        if !references.isEmpty { task += ". Use the reference material for notation" }
        parts.append(task + ".")

        return LecturePrompt(system: system, user: parts.joined(separator: "\n\n"), emptyFiles: emptyFiles)
    }
}
