//
//  LectureDetailView.swift
//  Lecture-Explainer
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
    // and the PDF text extraction behind the prompt are too slow for that.
    @State private var hasAPIKey = false
    @State private var prompt: LecturePrompt?
    @State private var copiedPrompt = false

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
                    // Opus 5.5 thinks before writing, which can take a while for a long deck.
                    Text(explainer.liveText.isEmpty ? "Claude is thinking…" : "Claude is writing…")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Stop", role: .destructive) { explainer.stop() }
                }
                if !explainer.liveText.isEmpty {
                    MarkdownView(markdown: explainer.liveText)
                }
            } else if lecture.sources.isEmpty {
                Text("Add a deck to this lecture to explain it.")
                    .foregroundStyle(.secondary)
            } else {
                if hasAPIKey {
                    Button("Explain with Claude", systemImage: "sparkles") {
                        explainer.explain([lecture], context: context)
                    }
                    .disabled(explainer.isRunning)
                }
                if let prompt {
                    // The share sheet lists the Claude app when it is installed.
                    ShareLink(item: prompt.combined,
                              preview: SharePreview("Lecture \(lecture.number) for Claude")) {
                        Label("Send to Claude App", systemImage: "square.and.arrow.up")
                    }
                    Button(copiedPrompt ? "Prompt Copied" : "Copy Prompt",
                           systemImage: copiedPrompt ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = prompt.combined
                        copiedPrompt = true
                    }
                }
                // Reading the clipboard makes iOS ask "Allow Paste?" (it can be set to
                // always allow under Settings > Lecture-Explainer). SwiftUI's PasteButton
                // avoids the question, but it is a fixed-style capsule that doesn't fit
                // a list of rows like these.
                Button("Paste Explanation", systemImage: "doc.on.clipboard") {
                    savePasted(UIPasteboard.general.string ?? "")
                }
            }

            if let failure = explainer.failure, failure.lecture == lecture {
                Text(failure.message)
                    .foregroundStyle(.red)
            }
            if let prompt, !prompt.emptyFiles.isEmpty {
                Text("No text found in \(prompt.emptyFiles.joined(separator: ", ")). Claude won't see these pages (scanned or image-only).")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Explain")
        } footer: {
            Text(hasAPIKey
                 ? "Explain with Claude uses your API key. Send to Claude App uses your Claude plan instead: send, copy Claude's answer there, then tap Paste Explanation here to save it."
                 : "Send to Claude App uses your Claude plan: send, copy Claude's answer there, then tap Paste Explanation here to save it. To explain directly in this app, save an API key in Settings.")
        }
        .task(id: copiedPrompt) {
            // Show "Prompt Copied" for two seconds, then go back to "Copy Prompt".
            guard copiedPrompt else { return }
            try? await Task.sleep(for: .seconds(2))
            copiedPrompt = false
        }
    }

    private func savePasted(_ text: String) {
        let markdown = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !markdown.isEmpty else { return }
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

/// An explanation, rendered from its Markdown, with a Copy button.
struct ExplanationView: View {
    let explanation: Explanation
    @State private var copied = false

    var body: some View {
        ScrollView {
            MarkdownView(markdown: explanation.markdown)
                .padding()
        }
        .navigationTitle(explanation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Copies the Markdown source, which pastes well into notes apps and
            // Claude alike.
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

#Preview {
    let container = SampleData.makeContainer()
    let lecture = try! container.mainContext.fetch(FetchDescriptor<Lecture>(sortBy: [SortDescriptor(\.number)])).first!
    NavigationStack {
        LectureDetailView(lecture: lecture)
    }
    .modelContainer(container)
    .environment(Explainer())
}
