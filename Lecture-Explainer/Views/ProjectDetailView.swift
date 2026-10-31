//
//  ProjectDetailView.swift
//  Lexia
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
    /// Opens the schedule editor straight away: used for a project just made from a
    /// template, whose copied lecture times need new semester dates.
    var opensSchedule = false
    @Environment(\.modelContext) private var context
    @Environment(Explainer.self) private var explainer

    @State private var editingSchedule = false
    @State private var addingLecture = false
    @State private var importingFiles = false
    @State private var importOutcome: (title: String, message: String)?
    @State private var confirmingExplainAll = false
    @State private var hasAPIKey = false

    /// Lectures with a deck and no explanation yet, in date order: what
    /// "Explain All Ready" sends.
    private var readyLectures: [Lecture] {
        project.lectures.filter { $0.status == .deckAdded }.sorted { $0.date < $1.date }
    }

    /// A new project shows a checklist of the steps to its first explanation until
    /// it has lectures and files.
    private var needsSetup: Bool {
        project.lectures.isEmpty || project.sources.isEmpty
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
            // The checklist covers instructions and schedule, so their own sections
            // only appear once the project is set up.
            if needsSetup {
                gettingStarted
            } else {
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

            if !sources.isEmpty {
                Section("Sources") {
                    ForEach(sources) { source in
                        NavigationLink {
                            SourceDetailView(source: source)
                        } label: {
                            SourceRow(source: source)
                        }
                    }
                }
            }

            if !needsSetup {
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
        .onAppear {
            hasAPIKey = KeychainStore.read() != nil
            if opensSchedule && project.lectures.isEmpty { editingSchedule = true }
        }
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
                importOutcome = (outcome.title, outcome.summary)
            case .failure(let error):
                importOutcome = ("Import Failed", error.localizedDescription)
            }
        }
        .alert(importOutcome?.title ?? "", isPresented: Binding(get: { importOutcome != nil },
                                                                set: { if !$0 { importOutcome = nil } })) {
            Button("OK") {}
        } message: {
            Text(importOutcome?.message ?? "")
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
                            Group {
                                if let retryAt = explainer.retryAt {
                                    Text("\(explainer.finished + 1) of \(explainer.total) · API busy, trying again \(retryAt, style: .relative)")
                                } else {
                                    Text("\(explainer.finished + 1) of \(explainer.total) · \(explainer.liveText.isEmpty ? "reading and thinking" : "writing")")
                                }
                            }
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
                Button(failure.remaining.count == 1 ? "Try Again" : "Try Again (\(failure.remaining.count) lectures)",
                       systemImage: "arrow.clockwise") {
                    explainer.retry(context: context)
                }
                Button("Dismiss") { explainer.dismissFailure() }
            }
        }
    }

    /// The three steps from a new project to its first explanation, each ticked off
    /// once done and each opening the place where it is done.
    @ViewBuilder private var gettingStarted: some View {
        Section {
            NavigationLink {
                InstructionsEditorView(project: project)
            } label: {
                SetupStep(done: !project.instructions.isEmpty, title: "Write instructions for Claude",
                          detail: "The level, language and format the explanations should have.")
            }
            Button {
                editingSchedule = true
            } label: {
                SetupStep(done: !project.lectures.isEmpty, title: "Set up the lecture schedule",
                          detail: "The weekly lecture times and the semester's dates.")
            }
            Button {
                importingFiles = true
            } label: {
                SetupStep(done: !project.sources.isEmpty, title: "Import the PDFs",
                          detail: "Slide decks named like QM4Eng_L05_….pdf go to the lecture with that number.")
            }
        } header: {
            Text("Get Started")
        } footer: {
            Text("Then open a lecture and explain it with Claude.")
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

/// One step of the Get Started checklist: a tick (or an empty circle), a title and a hint.
private struct SetupStep: View {
    let done: Bool
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(done ? Color.secondary : Color.primary)
                Text(detail)
                    .font(.caption)
                    // Color.secondary, not .secondary: inside a Button the latter takes
                    // the button's blue tint.
                    .foregroundStyle(Color.secondary)
            }
        }
        // VoiceOver hears the state as a value: "Import the PDFs, Done".
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : "Not done")
    }
}

/// "Week 4 · 26 Oct – 1 Nov", with a "This week" tag on the current one.
private struct WeekHeader: View {
    let week: Int
    let firstDate: Date
    let isCurrent: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let monday = mondayOfWeek(for: firstDate, in: calendar)
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday)!
        // The tag goes under the dates at the largest text sizes, as in LectureRow.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading))
            : AnyLayout(HStackLayout())
        layout {
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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At the largest (accessibility) text sizes the status goes below the date
        // instead of beside it, where it would squeeze the title to a few letters a line.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout())
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(lecture.title.isEmpty ? "Lecture \(lecture.number)" : "\(lecture.number). \(lecture.title)")
                // .dateTime formats follow the user's locale: "Tue 27 Oct, 10:15" or "Tue, Oct 27, 10:15 AM".
                Text(lecture.date, format: .dateTime.weekday(.abbreviated).day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !typeSize.isAccessibilitySize { Spacer() }
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
                .accessibilityHidden(true)   // the text says it; VoiceOver would read the icon's name too
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
