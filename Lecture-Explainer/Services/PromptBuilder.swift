//
//  PromptBuilder.swift
//  Lexia
//

import Foundation
import PDFKit

/// What Claude gets for one lecture: instructions, the lecture's PDFs, and the task.
/// The same prompt is used whether it goes through the API (Explainer) or is handed
/// to the Claude app by hand.
struct LecturePrompt: Equatable {
    /// A PDF that goes along with the prompt.
    struct Attachment: Equatable {
        var name: String
        var kind: SourceKind
        var url: URL
    }

    /// How to answer: the app's fixed rules plus the project's instructions.
    var system: String
    /// The lecture heading, what each attached PDF is, and the task.
    var user: String
    /// References first, then decks, then notes: the order they are sent in.
    var attachments: [Attachment] = []
    /// Files that can't be sent (missing from storage, password-protected or not a
    /// readable PDF), shown as a warning on the lecture screen.
    var unreadable: [String] = []

    /// Both parts in one text, for the Claude app, which has no separate field for
    /// a system prompt. The PDFs are shared alongside it.
    var combined: String { "\(system)\n\n---\n\n\(user)" }
}

/// Builds a LecturePrompt from a lecture and its files.
///
/// Decision: Claude gets the PDFs themselves, not text extracted on the phone. The
/// API reads each page as text *and* as an image, so scanned slides, diagrams and
/// equations drawn as pictures all come through. Text extraction (PDFReader) missed
/// those. The cost is a larger request: each page counts as text plus an image.
///
/// Split in two: `build(for:)` looks at the files, and the static `build(...)` below
/// only assembles text, so tests can check the exact prompt without files.
enum PromptBuilder {
    /// The fixed part of the system prompt. The project's own instructions are
    /// added after it, so they can refine or override the style.
    static let baseSystem = """
    You explain university lectures from their slide decks. The reader is a student \
    who wants to understand the lecture well enough to work with it: follow the deck \
    in order, refer to slides by their page number, explain what each slide says and \
    why, fill in steps the slides skip, and say what each symbol means when it first \
    appears. The slides are attached as PDFs; read formulas, diagrams and \
    handwriting from the page images too, not only from the text.

    Format the answer as Markdown: a "## Page n" heading (or "## Pages n–m" for \
    slides that belong together) for each part, short paragraphs, lists and tables \
    where they help. Write mathematics in LaTeX: $…$ inside a sentence and $$…$$ on \
    its own line for displayed equations. Don't use $ for anything else.
    """

    /// Finds the lecture's PDFs (and the project's references) and builds its prompt.
    static func build(for lecture: Lecture, store: FileStore = .shared) -> LecturePrompt {
        let project = lecture.project
        var attachments: [LecturePrompt.Attachment] = []
        var unreadable: [String] = []
        func collect(_ sources: [SourceMaterial]) -> [String] {
            // By slide first (notes for slide 4 before slide 22), then by name.
            let sorted = sources.sorted { ($0.slide ?? 0, $0.fileName) < ($1.slide ?? 0, $1.fileName) }
            var names: [String] = []
            for source in sorted {
                guard let path = source.storedPath, isSendablePDF(store.url(for: path)) else {
                    unreadable.append(source.fileName)
                    continue
                }
                attachments.append(.init(name: source.fileName, kind: source.kind, url: store.url(for: path)))
                names.append(source.fileName)
            }
            return names
        }
        let references = collect((project?.sources ?? []).filter { $0.kind == .reference })
        let decks = collect(lecture.sources.filter { $0.kind == .deck })
        let notes = collect(lecture.sources.filter { $0.kind == .notes })

        var prompt = build(courseName: project?.name ?? "", instructions: project?.instructions ?? "",
                           lectureNumber: lecture.number, lectureTitle: lecture.title, lectureDate: lecture.date,
                           references: references, decks: decks, notes: notes)
        prompt.attachments = attachments
        prompt.unreadable = unreadable
        return prompt
    }

    /// Whether the file opens as a PDF without a password.
    private static func isSendablePDF(_ url: URL) -> Bool {
        guard let document = PDFDocument(url: url) else { return false }
        return !document.isLocked
    }

    /// The bytes to send for an attachment. The API refuses encrypted PDFs. Many
    /// lecture PDFs are encrypted only to forbid copying or printing, and open without
    /// a password; for those, the pages are copied into a new, unencrypted document.
    /// (Saving the original again with dataRepresentation() would keep the encryption.)
    static func data(for attachment: LecturePrompt.Attachment) throws -> Data {
        if let document = PDFDocument(url: attachment.url), document.isEncrypted, !document.isLocked {
            let copy = PDFDocument()
            for index in 0..<document.pageCount {
                if let page = document.page(at: index)?.copy() as? PDFPage {
                    copy.insert(page, at: copy.pageCount)
                }
            }
            if let data = copy.dataRepresentation() { return data }
        }
        return try Data(contentsOf: attachment.url)
    }

    /// The prompt's text. `references`, `decks` and `notes` are the attached files' names.
    static func build(courseName: String, instructions: String,
                      lectureNumber: Int, lectureTitle: String, lectureDate: Date,
                      references: [String], decks: [String], notes: [String],
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

        // The PDFs arrive with their file names as titles; this list says what each one is.
        let files = references.map { "- \"\($0)\": reference sheet for notation" }
            + decks.map { "- \"\($0)\": the lecture's slide deck" }
            + notes.map { "- \"\($0)\": derivation notes that work out steps the slides only state" }
        var parts = [heading]
        if !files.isEmpty { parts.append("Attached PDFs:\n" + files.joined(separator: "\n")) }

        var task = "Explain lecture \(lectureNumber) using the slide deck"
        if !notes.isEmpty { task += " and the derivation notes" }
        if !references.isEmpty { task += ". Use the reference sheet's notation" }
        parts.append(task + ".")

        return LecturePrompt(system: system, user: parts.joined(separator: "\n\n"))
    }
}
