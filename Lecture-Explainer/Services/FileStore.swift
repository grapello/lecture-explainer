//
//  FileStore.swift
//  Lexia
//

import Foundation

/// The app's own copies of imported PDFs, on disk:
///
///     Application Support/Sources/<project.folderName>/<file name>.pdf
///
/// Why copy at all: a file picked in the Files app lives outside the app's sandbox
/// and is only readable for a moment (see SourceImporter). Keeping a copy means the
/// deck is still there after a relaunch, even if the original is moved or deleted.
///
/// Application Support (not Documents) because these are app data, not files the
/// user manages; it is backed up but not shown in the Files app.
struct FileStore {
    let baseURL: URL

    /// The real store. Tests create their own FileStore on a temporary folder.
    static let shared = FileStore(baseURL: URL.applicationSupportDirectory.appending(path: "Sources"))

    /// Copies `source` into the project's folder and returns its stored path
    /// ("<folder>/<file name>"), which is what SourceMaterial.storedPath keeps.
    /// A file with the same name is replaced: importing a corrected deck updates it.
    func copyIn(_ source: URL, projectFolder: String) throws -> String {
        let folder = baseURL.appending(path: projectFolder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: source.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return "\(projectFolder)/\(source.lastPathComponent)"
    }

    /// The full URL for a stored path. Built fresh each time from the current
    /// base folder, which is why only the relative path is saved.
    func url(for storedPath: String) -> URL {
        baseURL.appending(path: storedPath)
    }

    func remove(storedPath: String) {
        // try?: a file that is already gone is fine; there is nothing to clean up.
        try? FileManager.default.removeItem(at: url(for: storedPath))
    }

    /// Deletes a project's whole folder. SwiftData's cascade deletes the
    /// SourceMaterial records, but it doesn't know about files on disk.
    func removeFolder(_ projectFolder: String) {
        try? FileManager.default.removeItem(at: baseURL.appending(path: projectFolder, directoryHint: .isDirectory))
    }
}
