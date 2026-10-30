//
//  Explainer.swift
//  Lecture-Explainer
//

import Foundation
import Observation
import SwiftData

/// Sends lectures to Claude through the API, one after another, and saves each
/// answer as an Explanation.
///
/// One Explainer lives for the whole app (created in MyApp and passed down with
/// `.environment`), not inside a screen. So a run keeps going, and stays visible,
/// when you leave the lecture or project screen that started it.
///
/// @Observable: SwiftUI redraws every view that reads `liveText`, `current`, … when
/// they change, which is how the answer appears word by word.
@Observable
final class Explainer {
    /// The lecture being written right now.
    private(set) var current: Lecture?
    /// The answer so far for `current`.
    private(set) var liveText = ""
    /// Lectures finished in this run, and how many the run has in total.
    private(set) var finished = 0
    private(set) var total = 0
    /// Why the last run stopped early, shown on the project and lecture screens.
    private(set) var failure: (lecture: Lecture, message: String)?

    private var queue: [Lecture] = []
    private var task: Task<Void, Never>?

    var isRunning: Bool { task != nil }

    /// Where requests go. The real one uses the API key from the Keychain; tests put a
    /// fake stream here, so they need no key or network.
    var send: (ClaudeRequest) throws -> AsyncThrowingStream<String, Error> = { request in
        try ClaudeClient.fromKeychain().stream(request)
    }

    /// Starts explaining `lectures` in this order. Does nothing while a run is going.
    func explain(_ lectures: [Lecture], context: ModelContext) {
        guard task == nil, !lectures.isEmpty else { return }
        queue = lectures
        total = lectures.count
        finished = 0
        failure = nil
        task = Task { await run(context: context) }
    }

    /// Stops the run. The lecture being written is not saved; finished ones are kept.
    func stop() {
        task?.cancel()
    }

    /// Waits until the current run has ended (used by tests).
    func waitUntilFinished() async {
        await task?.value
    }

    private func run(context: ModelContext) async {
        defer {
            current = nil
            liveText = ""
            queue = []
            task = nil
        }
        while !queue.isEmpty {
            let lecture = queue.removeFirst()
            current = lecture
            liveText = ""
            do {
                let prompt = PromptBuilder.build(for: lecture)
                // At least one of the lecture's own files must have text; otherwise
                // Claude would get only the task and make the lecture up.
                guard lecture.sources.contains(where: { !prompt.emptyFiles.contains($0.fileName) }) else {
                    throw ExplainerError.noText
                }
                let request = ClaudeRequest(model: Self.model, effort: Self.effort,
                                            system: prompt.system, userText: prompt.user)
                for try await piece in try send(request) {
                    liveText += piece
                }
                // When the Task is cancelled, the stream simply ends, as if the answer
                // were complete. Checking here keeps a half-written answer from being saved.
                try Task.checkCancellation()
                save(liveText, for: lecture, context: context)
                finished += 1
            } catch is CancellationError {
                return
            } catch {
                // Stop the whole run: the usual causes (no credit, invalid key, rate
                // limit) would make every following lecture fail the same way.
                failure = (lecture, error.localizedDescription)
                return
            }
        }
    }

    private func save(_ markdown: String, for lecture: Lecture, context: ModelContext) {
        let title = lecture.title.isEmpty ? "Lecture \(lecture.number)" : "Lecture \(lecture.number): \(lecture.title)"
        let explanation = Explanation(markdown: markdown, title: title)
        explanation.lecture = lecture
        // Saved right away, so a finished explanation survives the app being closed
        // during the next lecture of a long run.
        try? context.save()
    }

    // The model and effort chosen in Settings. @AppStorage there stores them in
    // UserDefaults under these keys, as their raw values.
    private static var model: ClaudeModel {
        ClaudeModel(rawValue: UserDefaults.standard.string(forKey: "claudeModel") ?? "") ?? .opus
    }
    private static var effort: ClaudeEffort {
        ClaudeEffort(rawValue: UserDefaults.standard.string(forKey: "claudeEffort") ?? "") ?? .high
    }
}

enum ExplainerError: LocalizedError {
    case noText

    var errorDescription: String? {
        switch self {
        case .noText: "Nothing to send: this lecture has no file with readable text. Scanned or image-only pages give no text."
        }
    }
}
