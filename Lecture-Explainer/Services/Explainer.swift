//
//  Explainer.swift
//  Lexia
//

import Foundation
import Observation
import SwiftData
import SwiftUI

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
    /// When the API was busy: the time of the next attempt (shown as a countdown).
    private(set) var retryAt: Date?
    /// Why the last run stopped early, shown on the project and lecture screens, and
    /// the lectures it didn't get to (the failed one first), for "Try Again".
    private(set) var failure: (lecture: Lecture, message: String, remaining: [Lecture])?

    private var queue: [Lecture] = []
    private var replacing = false
    private var task: Task<Void, Never>?

    var isRunning: Bool { task != nil }

    /// Where requests go. The real one uses the API key from the Keychain; tests put a
    /// fake stream here, so they need no key or network.
    var send: (ClaudeRequest) throws -> AsyncThrowingStream<String, Error> = { request in
        try ClaudeClient.fromKeychain().stream(request)
    }
    /// How waiting before a retry is done; tests make it instant.
    var sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    /// Waits between attempts when the API is overloaded, rate-limited or has a server
    /// error, unless the API says how long to wait (`retry-after`). After the last one
    /// the run stops with the error.
    static let retryDelays: [Duration] = [.seconds(15), .seconds(45), .seconds(120)]

    /// Starts explaining `lectures` in this order. With `replacing`, a lecture's
    /// existing explanations are deleted once its new one is saved (not before, so a
    /// failed request never loses the old one). Does nothing while a run is going.
    func explain(_ lectures: [Lecture], replacing: Bool = false, context: ModelContext) {
        guard task == nil, !lectures.isEmpty else { return }
        queue = lectures
        self.replacing = replacing
        total = lectures.count
        finished = 0
        failure = nil
        task = Task { await run(context: context) }
    }

    /// Continues a run that stopped: the failed lecture and the ones after it,
    /// replacing old explanations if the first attempt was going to.
    func retry(context: ModelContext) {
        guard let failure else { return }
        explain(failure.remaining, replacing: replacing, context: context)
    }

    /// Hides the "stopped at…" message, e.g. after the user has read it.
    func dismissFailure() {
        failure = nil
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
            retryAt = nil
            queue = []
            task = nil
        }
        while !queue.isEmpty {
            let lecture = queue.removeFirst()
            current = lecture
            do {
                let request = try Self.request(for: lecture)
                let answer = try await answerWithRetries(request)
                save(answer, for: lecture, context: context)
                finished += 1
                // A run can take minutes; VoiceOver users hear when each lecture is done,
                // whichever screen they are on.
                announce("Lecture \(lecture.number) explained")
            } catch is CancellationError {
                return
            } catch {
                // Stop the whole run: the usual causes (no credit, invalid key) would
                // make every following lecture fail the same way.
                failure = (lecture, error.localizedDescription, [lecture] + queue)
                announce("Explaining stopped at Lecture \(lecture.number). \(error.localizedDescription)")
                return
            }
        }
    }

    /// Streams one answer into `liveText`. A busy API (overloaded, rate limit,
    /// server error) gets a few more tries after a pause; the answer starts over
    /// each time, because a broken-off stream can't be resumed.
    private func answerWithRetries(_ request: ClaudeRequest) async throws -> String {
        var attempt = 0
        while true {
            liveText = ""
            do {
                for try await piece in try send(request) {
                    liveText += piece
                }
                // When the Task is cancelled, the stream simply ends, as if the answer
                // were complete. Checking here keeps a half-written answer from being saved.
                try Task.checkCancellation()
                return liveText
            } catch let error as ClaudeError where error.isRetryable && attempt < Self.retryDelays.count {
                let delay = error.retryAfter.map { Duration.seconds($0) } ?? Self.retryDelays[attempt]
                attempt += 1
                retryAt = .now.addingTimeInterval(TimeInterval(delay.components.seconds))
                defer { retryAt = nil }
                try await sleep(delay)
            }
        }
    }

    /// The API request for one lecture: the prompt plus its PDFs.
    private static func request(for lecture: Lecture) throws -> ClaudeRequest {
        let prompt = PromptBuilder.build(for: lecture)
        // Without at least one of the lecture's own files, Claude would get only the
        // task and make the lecture up.
        guard prompt.attachments.contains(where: { $0.kind != .reference }) else {
            throw ExplainerError.noFiles
        }
        var documents = try prompt.attachments.map { attachment in
            ClaudeDocument(title: attachment.name, data: try PromptBuilder.data(for: attachment))
        }
        // The system prompt and the reference sheets are the same for every lecture of
        // the project, so the cache marker goes after the last reference (see
        // ClaudeClient.blocks).
        if let lastReference = prompt.attachments.lastIndex(where: { $0.kind == .reference }) {
            documents[lastReference].cacheUpToHere = true
        }
        // The API takes up to 128 MB per request; base64 makes files a third larger.
        let bytes = documents.reduce(0) { $0 + $1.data.count }
        guard bytes < 90_000_000 else { throw ExplainerError.tooLarge(megabytes: bytes / 1_000_000) }

        return ClaudeRequest(model: model, effort: effort, system: prompt.system,
                             documents: documents, userText: prompt.user)
    }

    private func save(_ markdown: String, for lecture: Lecture, context: ModelContext) {
        let old = replacing ? lecture.explanations : []
        let title = lecture.title.isEmpty ? "Lecture \(lecture.number)" : "Lecture \(lecture.number): \(lecture.title)"
        let explanation = Explanation(markdown: markdown, title: title)
        explanation.lecture = lecture
        for explanation in old { context.delete(explanation) }
        // Saved right away, so a finished explanation survives the app being closed
        // during the next lecture of a long run.
        try? context.save()
    }

    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
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

enum ExplainerError: LocalizedError, Equatable {
    case noFiles
    case tooLarge(megabytes: Int)

    var errorDescription: String? {
        switch self {
        case .noFiles: "Nothing to send: none of this lecture's files can be opened. Import the deck again."
        case .tooLarge(let megabytes): "The lecture's PDFs are \(megabytes) MB together, too large for one request (about 90 MB at most)."
        }
    }
}

extension ClaudeError {
    /// The wait the API asked for, in seconds, if it said.
    var retryAfter: Int? {
        if case .rateLimited(let seconds) = self { return seconds }
        return nil
    }
}
