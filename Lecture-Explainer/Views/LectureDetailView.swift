//
//  LectureDetailView.swift
//  Lexia
//

import SwiftUI
import SwiftData
import UIKit

/// One lecture: its date (editable with a calendar), title, files and explanations.
struct LectureDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Explainer.self) private var explainer
    @Bindable var lecture: Lecture
    @State private var confirmingDelete = false

    // Read when the screen appears rather than on every redraw: the Keychain read
    // and opening the PDFs behind the prompt are too slow for that.
    @State private var hasAPIKey = false
    @State private var prompt: LecturePrompt?
    @State private var copiedPrompt = false
    @State private var sharing = false
    @State private var clipboardEmpty = false

    /// The two ways a new explanation arrives. Kept while the "replace or keep
    /// both?" question is open, so the answer knows what to continue with.
    private enum NewExplanation { case api, paste }
    @State private var askingToReplace: NewExplanation?

    private var explanations: [Explanation] {
        lecture.explanations.sorted { $0.createdAt > $1.createdAt }
    }

    /// A binding that does more than store the date: a date picked by hand marks the
    /// lecture as manual (so re-applying the schedule leaves it alone) and renumbers
    /// the project, because moving a lecture can change the order.
    private var date: Binding<Date> {
        Binding(
            get: { lecture.date },
            set: { newDate in
                lecture.date = newDate
                lecture.isManual = true
                if let project = lecture.project { SchedulePlanner.renumber(project) }
            })
    }

    var body: some View {
        Form {
            Section {
                TextField("Title (optional)", text: $lecture.title)
            }

            Section {
                DatePicker("Date", selection: date)
                    .datePickerStyle(.graphical)
            } header: {
                Text("Date")
            } footer: {
                if lecture.isManual {
                    Text("Set by hand. Saving the schedule won't move or remove this lecture.")
                }
            }

            Section("Files") {
                if lecture.sources.isEmpty {
                    Text("No files. Import a PDF named like QM4Eng_L\(String(format: "%02d", lecture.number))_….pdf, or assign one from the Sources list.")
                        .foregroundStyle(.secondary)
                }
                ForEach(lecture.sources) { source in
                    NavigationLink {
                        SourceDetailView(source: source)
                    } label: {
                        SourceRow(source: source)
                    }
                }
            }

            explainSection

            Section("Explanations") {
                if explanations.isEmpty {
                    Text("Not explained yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(explanations) { explanation in
                    NavigationLink {
                        ExplanationView(explanation: explanation)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(explanation.title.isEmpty ? "Untitled" : explanation.title)
                            Text(explanation.createdAt, format: .dateTime.day().month().year().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                // Swipe left to delete, e.g. an older version after explaining again.
                .onDelete { offsets in
                    for index in offsets { context.delete(explanations[index]) }
                }
            }

            Section {
                Button("Delete Lecture", role: .destructive) { confirmingDelete = true }
            }
        }
        .navigationTitle("Lecture \(lecture.number)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            hasAPIKey = KeychainStore.read() != nil
            prompt = PromptBuilder.build(for: lecture)
        }
        // Files added or removed elsewhere change what the prompt contains.
        .onChange(of: lecture.sources.count) {
            prompt = PromptBuilder.build(for: lecture)
        }
        .confirmationDialog("Delete Lecture \(lecture.number)?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete Lecture", role: .destructive) { delete() }
        } message: {
            Text("Its explanations are deleted. Its files stay in the project, unassigned.")
        }
    }

    // MARK: - Explaining

    /// Two ways to get an explanation:
    /// - "Explain with Claude": through the API with the saved key (Explainer); the
    ///   answer streams in right here and is saved when it is complete.
    /// - "Send to Claude App": hands the same prompt to the Claude app via the share
    ///   sheet (or Copy Prompt), so it runs on the user's Claude plan. The answer comes
    ///   back by copying it there and tapping Paste here.
    @ViewBuilder private var explainSection: some View {
        Section {
            if explainer.current == lecture {
                HStack {
                    ProgressView()
                    if let retryAt = explainer.retryAt {
                        // A busy API: the answer starts over at retryAt.
                        Text("API busy, trying again \(retryAt, style: .relative)")
                            .foregroundStyle(.secondary)
                    } else {
                        // Opus 5.5 thinks before writing, which can take a while for a long deck.
                        Text(explainer.liveText.isEmpty ? "Claude is reading and thinking…" : "Claude is writing…")
                            .foregroundStyle(.secondary)
                    }
                }
                // Its own row rather than at the end of the line above, which leaves no
                // room for the status text at large text sizes.
                Button("Stop", systemImage: "stop.circle", role: .destructive) { explainer.stop() }
                if !explainer.liveText.isEmpty {
                    MathMarkdownView(markdown: explainer.liveText, scrolls: false)
                        // Edge to edge inside the row; the page has its own margins.
                        .listRowInsets(EdgeInsets())
                }
            } else if lecture.sources.isEmpty {
                Text("Add a deck to this lecture to explain it.")
                    .foregroundStyle(.secondary)
            } else {
                if hasAPIKey {
                    Button("Explain with Claude", systemImage: "sparkles") { start(.api) }
                        .disabled(explainer.isRunning)
                }
                if let prompt {
                    // The share sheet gets the prompt and the PDFs together; it lists
                    // the Claude app when it is installed.
                    Button("Send to Claude App", systemImage: "square.and.arrow.up") { sharing = true }
                    Button(copiedPrompt ? "Prompt Copied" : "Copy Prompt",
                           systemImage: copiedPrompt ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = prompt.combined
                        copiedPrompt = true
                    }
                }
                // Reading the clipboard makes iOS ask "Allow Paste?" (it can be set to
                // always allow under Settings > Lexia). SwiftUI's PasteButton
                // avoids the question, but it is a fixed-style capsule that doesn't fit
                // a list of rows like these.
                Button("Paste Explanation", systemImage: "doc.on.clipboard") { start(.paste) }
            }

            if let failure = explainer.failure, failure.lecture == lecture {
                Label(failure.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Button("Try Again", systemImage: "arrow.clockwise") { explainer.retry(context: context) }
                    .disabled(explainer.isRunning)
            }
            if let prompt, !prompt.unreadable.isEmpty {
                Text("Can't send \(prompt.unreadable.joined(separator: ", ")): the file is missing or needs a password.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Explain")
        } footer: {
            Text(hasAPIKey
                 ? "Explain with Claude uses your API key. Send to Claude App uses your Claude plan instead: send the prompt and PDFs, copy Claude's answer there, then tap Paste Explanation here to save it."
                 : "Send to Claude App uses your Claude plan: send the prompt and PDFs, copy Claude's answer there, then tap Paste Explanation here to save it. To explain directly in this app, save an API key in Settings.")
        }
        .sheet(isPresented: $sharing) {
            if let prompt {
                ShareSheet(items: [prompt.combined] + prompt.attachments.map(\.url))
            }
        }
        // Explaining again or pasting when an explanation exists: replace it, or keep both?
        .confirmationDialog("Lecture \(lecture.number) already has an explanation",
                            isPresented: Binding(get: { askingToReplace != nil },
                                                 set: { if !$0 { askingToReplace = nil } }),
                            titleVisibility: .visible, presenting: askingToReplace) { kind in
            Button("Replace the Old One", role: .destructive) { finish(kind, replacing: true) }
            Button("Keep Both") { finish(kind, replacing: false) }
        } message: { kind in
            Text(kind == .api
                 ? "Replace deletes the old explanation once the new one has been saved."
                 : "Replace deletes the old explanation and saves the pasted one.")
        }
        .alert("Nothing to Paste", isPresented: $clipboardEmpty) {
            Button("OK") {}
        } message: {
            Text("The clipboard has no text. In the Claude app, tap Copy under Claude's answer, then come back and tap Paste Explanation.")
        }
        .task(id: copiedPrompt) {
            // Show "Prompt Copied" for two seconds, then go back to "Copy Prompt".
            guard copiedPrompt else { return }
            try? await Task.sleep(for: .seconds(2))
            copiedPrompt = false
        }
    }

    /// Asks "replace or keep both?" first if the lecture is already explained.
    private func start(_ kind: NewExplanation) {
        // Nothing to paste: say so now, rather than after the replace question.
        if kind == .paste && (UIPasteboard.general.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clipboardEmpty = true
        } else if lecture.explanations.isEmpty {
            finish(kind, replacing: false)
        } else {
            askingToReplace = kind
        }
    }

    private func finish(_ kind: NewExplanation, replacing: Bool) {
        switch kind {
        case .api:
            explainer.explain([lecture], replacing: replacing, context: context)
        case .paste:
            savePasted(UIPasteboard.general.string ?? "", replacing: replacing)
        }
    }

    private func savePasted(_ text: String, replacing: Bool) {
        let markdown = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !markdown.isEmpty else { return }
        if replacing {
            for old in lecture.explanations { context.delete(old) }
        }
        let title = lecture.title.isEmpty ? "Lecture \(lecture.number)" : "Lecture \(lecture.number): \(lecture.title)"
        let explanation = Explanation(markdown: markdown, title: title)
        explanation.lecture = lecture
    }

    private func delete() {
        let project = lecture.project
        context.delete(lecture)
        if let project { SchedulePlanner.renumber(project) }
        dismiss()
    }
}

/// Sheet for adding a lecture outside the weekly schedule (an extra session, a
/// rescheduled one). It is marked manual, so the schedule never removes it.
struct AddLectureView: View {
    @Environment(\.dismiss) private var dismiss
    let project: Project
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date)
                    .datePickerStyle(.graphical)
            }
            .navigationTitle("Add Lecture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let lecture = Lecture(number: 0, date: date, isManual: true)
                        lecture.project = project
                        SchedulePlanner.renumber(project)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// An explanation, rendered from its Markdown with typeset formulas, with a Copy button.
struct ExplanationView: View {
    let explanation: Explanation
    @State private var copied = false

    var body: some View {
        MathMarkdownView(markdown: explanation.markdown)
        .navigationTitle(explanation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Copies the Markdown source (formulas as LaTeX), which pastes well into
            // notes apps, Obsidian and Claude alike.
            Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                UIPasteboard.general.string = explanation.markdown
                copied = true
            }
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

/// The system share sheet (UIActivityViewController). SwiftUI's ShareLink can't
/// share a text and several files in one go, which "Send to Claude App" needs.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview {
    let container = SampleData.makeContainer()
    let lecture = try! container.mainContext.fetch(FetchDescriptor<Lecture>(sortBy: [SortDescriptor(\.number)])).first!
    NavigationStack {
        LectureDetailView(lecture: lecture)
    }
    .modelContainer(container)
    .environment(Explainer())
}
