//
//  ProjectDetailView.swift
//  Lecture-Explainer
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// One project: its instructions, its schedule, its lectures grouped by week,
/// its files and its explanations. The + menu imports PDFs, adds a lecture by
/// hand, or opens the schedule editor.
struct ProjectDetailView: View {
    // @Bindable lets this view hand out bindings into the model ($project.name, ...).
    // Plain `let project` would be enough to read it; editing needs @Bindable.
    @Bindable var project: Project
    @Environment(\.modelContext) private var context
    @Environment(Explainer.self) private var explainer

    @State private var editingSchedule = false
    @State private var addingLecture = false
    @State private var importingFiles = false
    @State private var importMessage: String?
    @State private var confirmingExplainAll = false
    @State private var hasAPIKey = false

    /// Lectures with a deck and no explanation yet, in date order: what
    /// "Explain All Ready" sends.
    private var readyLectures: [Lecture] {
        project.lectures.filter { $0.status == .deckAdded }.sorted { $0.date < $1.date }
    }

    /// Whether the Explainer's current or failed run belongs to this project.
    private var showsRun: Bool {
        explainer.current?.project == project || explainer.failure?.lecture.project == project
    }

    // Computed on each redraw from the stored lecture dates, so a lecture moved by
    // hand lands in its new week straight away. `\.date` works as a (Lecture) -> Date closure.
    private var weeks: [(week: Int, items: [Lecture])] {
        WeekCalendar.groupedByWeek(project.lectures, date: \.date, calendar: calendar)
    }

    /// The week today falls in, or nil before the first lecture's week / without lectures.
    private var currentWeek: Int? {
        guard let first = project.lectures.map(\.date).min(), first <= .now else { return nil }
        return WeekCalendar.weekNumber(date: .now, firstLecture: first, calendar: calendar)
    }

    private var explanations: [Explanation] {
        project.lectures.flatMap(\.explanations).sorted { $0.createdAt > $1.createdAt }
    }

    // Project-wide files (no lecture) first, then by lecture number.
    private var sources: [SourceMaterial] {
        project.sources.sorted { ($0.lecture?.number ?? 0, $0.fileName) < ($1.lecture?.number ?? 0, $1.fileName) }
    }

    var body: some View {
        List {
            if showsRun {
                runSection
            }

            Section("Instructions") {
                NavigationLink {
                    InstructionsEditorView(project: project)
                } label: {
                    if project.instructions.isEmpty {
                        Text("Add instructions for Claude")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(project.instructions)
                            .lineLimit(3)
                    }
                }
            }

            Section("Schedule") {
                Button {
                    editingSchedule = true
                } label: {
                    Label(scheduleSummary, systemImage: "calendar")
                }
            }

            if weeks.isEmpty {
                Section("Weeks") {
                    Text("No lectures yet. Set up the schedule, or add a lecture from the + menu.")
                        .foregroundStyle(.secondary)
                }
            }
            // One section per week. A Section can't sit inside another Section, so the
            // weeks are top-level sections between Schedule and Sources.
            ForEach(weeks, id: \.week) { group in
                let isCurrent = group.week == currentWeek
                Section {
                    ForEach(group.items) { lecture in
                        NavigationLink {
                            LectureDetailView(lecture: lecture)
                        } label: {
                            LectureRow(lecture: lecture)
                        }
                        // A light tint of the app's accent colour marks this week's lectures.
                        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.12) : nil)
                    }
                } header: {
                    WeekHeader(week: group.week, firstDate: group.items[0].date, isCurrent: isCurrent)
                }
            }

            Section("Sources") {
                if sources.isEmpty {
                    Text("No files yet. Import PDFs from the + menu.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sources) { source in
                    NavigationLink {
                        SourceDetailView(source: source)
                    } label: {
                        SourceRow(source: source)
                    }
                }
            }

            Section("Explanations") {
                if explanations.isEmpty {
                    Text("No explanations yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(explanations) { explanation in
                    NavigationLink {
                        ExplanationView(explanation: explanation)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(explanation.title.isEmpty ? "Untitled" : explanation.title)
                            Text(explanation.createdAt, format: .dateTime.day().month().year())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(project.name)
        .toolbar {
            if hasAPIKey {
                // A separate button, not in the + menu: it is the main thing to do here.
                Button("Explain All Ready", systemImage: "sparkles") { confirmingExplainAll = true }
                    .disabled(readyLectures.isEmpty || explainer.isRunning)
            }
            Menu("Add", systemImage: "plus") {
                Button("Import PDFs", systemImage: "doc.badge.plus") { importingFiles = true }
                Button("Add Lecture", systemImage: "calendar.badge.plus") { addingLecture = true }
                Button("Edit Schedule", systemImage: "calendar") { editingSchedule = true }
            }
        }
        .onAppear { hasAPIKey = KeychainStore.read() != nil }
        // Explaining costs API credit, so a run of several lectures asks first.
        .confirmationDialog("Explain \(readyLectures.count) lecture\(readyLectures.count == 1 ? "" : "s") with Claude?",
                            isPresented: $confirmingExplainAll, titleVisibility: .visible) {
            Button("Explain \(readyLectures.count)") {
                explainer.explain(readyLectures, context: context)
            }
        } message: {
            Text("Every lecture with a deck and no explanation yet is sent, one after another. This uses your API credit.")
        }
        .sheet(isPresented: $editingSchedule) {
            ScheduleEditorView(project: project)
        }
        .sheet(isPresented: $addingLecture) {
            AddLectureView(project: project)
        }
        // The system Files picker. It hands back URLs outside the app's sandbox,
        // which SourceImporter copies in (see the comments there).
        .fileImporter(isPresented: $importingFiles, allowedContentTypes: [.pdf],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                let outcome = SourceImporter.importFiles(urls, into: project)
                importMessage = outcome.summary
            case .failure(let error):
                importMessage = error.localizedDescription
            }
        }
        .alert("Import", isPresented: Binding(get: { importMessage != nil },
                                              set: { if !$0 { importMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    /// Progress of an "Explain" run, or why it stopped. Tapping the lecture opens
    /// it, where the answer can be watched as it is written.
    @ViewBuilder private var runSection: some View {
        Section("Explaining") {
            if let lecture = explainer.current {
                NavigationLink {
                    LectureDetailView(lecture: lecture)
                } label: {
                    HStack {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lecture \(lecture.number)")
                            Text("\(explainer.finished + 1) of \(explainer.total) · \(explainer.liveText.isEmpty ? "thinking" : "writing")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Stop", role: .destructive) { explainer.stop() }
            } else if let failure = explainer.failure {
                Label("Stopped at Lecture \(failure.lecture.number): \(failure.message)",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }

    /// "Tue 10:15, Thu 14:00 · 13 Oct – 2 Feb", or a prompt when there is no schedule.
    private var scheduleSummary: String {
        let rules = project.scheduleRules.sorted { ($0.weekday + 5) % 7 < ($1.weekday + 5) % 7 }
        guard let first = rules.first else { return "Set up weekly lectures" }
        let slots = rules.map { rule in
            let day = calendar.shortWeekdaySymbols[rule.weekday - 1]
            return "\(day) \(String(format: "%02d:%02d", rule.hour, rule.minute))"
        }.joined(separator: ", ")
        let range = first.startDate.formatted(.dateTime.day().month(.abbreviated)) + " – "
            + first.endDate.formatted(.dateTime.day().month(.abbreviated))
        return "\(slots) · \(range)"
    }
}

/// "Week 4 · 26 Oct – 1 Nov", with a "This week" tag on the current one.
private struct WeekHeader: View {
    let week: Int
    let firstDate: Date
    let isCurrent: Bool

    var body: some View {
        let monday = mondayOfWeek(for: firstDate, in: calendar)
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday)!
        HStack {
            Text("Week \(week) · \(monday.formatted(.dateTime.day().month(.abbreviated))) – \(sunday.formatted(.dateTime.day().month(.abbreviated)))")
            if isCurrent {
                Text("This week")
                    .font(.caption.bold())
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}

private struct LectureRow: View {
    let lecture: Lecture

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lecture.title.isEmpty ? "Lecture \(lecture.number)" : "\(lecture.number). \(lecture.title)")
                // .dateTime formats follow the user's locale: "Tue 27 Oct, 10:15" or "Tue, Oct 27, 10:15 AM".
                Text(lecture.date, format: .dateTime.weekday(.abbreviated).day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            status
                .font(.caption)
        }
    }

    // System colours (.green, .orange, .secondary) have light and dark variants,
    // so these labels stay readable in both modes without extra code.
    @ViewBuilder private var status: some View {
        if !WeekCalendar.isDue(date: lecture.date) {
            StatusLabel(text: "Not due yet", icon: "clock", color: .secondary)
        } else {
            switch lecture.status {
            case .explained:
                StatusLabel(text: "Explained", icon: "checkmark.circle.fill", color: .green)
            case .deckAdded:
                StatusLabel(text: "Ready", icon: "doc.fill", color: .blue)
            case .needsDeck:
                StatusLabel(text: "Needs deck", icon: "exclamationmark.circle", color: .orange)
            }
        }
    }
}

/// Icon and text close together. A plain Label inside a List row spaces them
/// like a list item, which leaves a wide gap at this small size.
private struct StatusLabel: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .foregroundStyle(color)
    }
}

#Preview {
    // Fetch the sample project out of the preview store to show it.
    let container = SampleData.makeContainer()
    let project = try! container.mainContext.fetch(
        FetchDescriptor<Project>(predicate: #Predicate { $0.name.contains("Quantum") })).first!
    NavigationStack {
        ProjectDetailView(project: project)
    }
    .modelContainer(container)
    .environment(Explainer())
}
