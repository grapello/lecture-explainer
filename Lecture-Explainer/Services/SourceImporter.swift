//
//  SourceImporter.swift
//  Lexia
//

import Foundation
import SwiftData

/// Turns picked PDF files into SourceMaterial records: copies each file into the
/// app's storage, reads its name with FileNameParser, and links it to the lecture
/// with that number.
enum SourceImporter {
    struct Outcome {
        var imported: [SourceMaterial] = []
        var failed: [(fileName: String, error: Error)] = []

        /// Files that are neither linked to a lecture nor project-wide references:
        /// the name had no lecture number, or no lecture has that number yet.
        var unassigned: [SourceMaterial] {
            imported.filter { $0.lecture == nil && $0.kind != .reference }
        }

        /// A short message for the alert after an import.
        var summary: String {
            var lines = ["Imported \(imported.count) file\(imported.count == 1 ? "" : "s")."]
            if !unassigned.isEmpty {
                lines.append("Not linked to a lecture: \(unassigned.map(\.fileName).joined(separator: ", ")). Open a file to choose its lecture.")
            }
            for failure in failed {
                lines.append("Could not import \(failure.fileName): \(failure.error.localizedDescription)")
            }
            return lines.joined(separator: "\n\n")
        }
    }

    @discardableResult
    static func importFiles(_ urls: [URL], into project: Project, store: FileStore = .shared) -> Outcome {
        var outcome = Outcome()
        for url in urls {
            // Files from the picker are "security-scoped": the app may read them only
            // between start… and stop…. Without this the copy fails with a permission
            // error on a real device. It returns false for files that are already
            // inside the sandbox (as in the tests), which is fine.
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            do {
                let storedPath = try store.copyIn(url, projectFolder: project.folderName)
                let name = url.lastPathComponent
                let parsed = FileNameParser.parse(name)

                // Importing a file with the same name again updates the existing record
                // (the file itself was just replaced) instead of adding a duplicate.
                let source = project.sources.first { $0.fileName == name }
                    ?? SourceMaterial(fileName: name, kind: parsed.kind)
                source.kind = parsed.kind
                source.slide = parsed.slide
                source.storedPath = storedPath
                source.project = project   // also inserts a new record into the context

                // Link to the lecture with the number from the name, unless the file
                // was already linked (possibly by hand) or is a project-wide reference.
                if source.lecture == nil, parsed.kind != .reference, let number = parsed.lectureNumber {
                    source.lecture = project.lectures.first { $0.number == number }
                }
                outcome.imported.append(source)
            } catch {
                outcome.failed.append((url.lastPathComponent, error))
            }
        }
        return outcome
    }

    /// Deletes a source: its file on disk and its record.
    static func remove(_ source: SourceMaterial, context: ModelContext, store: FileStore = .shared) {
        if let storedPath = source.storedPath { store.remove(storedPath: storedPath) }
        context.delete(source)
    }
}
