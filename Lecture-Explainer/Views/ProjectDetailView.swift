//
//  ProjectDetailView.swift
//  Lecture-Explainer
//

import SwiftUI
import SwiftData

/// One project: its instructions, its lectures grouped by week, its files and
/// its explanations. The week list gets its full version in roadmap step 3.
struct ProjectDetailView: View {
    // @Bindable lets this view hand out bindings into the model ($project.name, ...).
    // Plain `let project` would be enough to read it; editing needs @Bindable.
    @Bindable var project: Project

    // Computed on each redraw from the stored lecture dates, so a lecture moved by
    // hand lands in its new week straight away. `\.date` works as a (Lecture) -> Date closure.
    private var weeks: [(week: Int, items: [Lecture])] {
        WeekCalendar.groupedByWeek(project.lectures, date: \.date, calendar: calendar)
    }

    private var explanations: [Explanation] {
        project.lectures.flatMap(\.explanations).sorted { $0.createdAt > $1.createdAt }
    }

    // Project-wide files (no lecture) first, then by lecture number.
    private var sources: [SourceMaterial] {
        project.sources.sorted { ($0.lecture?.number ?? 0) < ($1.lecture?.number ?? 0) }
    }

    var body: some View {
        List {
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

            Section("Weeks") {
                if weeks.isEmpty {
                    Text("No lectures yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(weeks, id: \.week) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Week \(group.week)")
                            .font(.headline)
                        ForEach(group.items) { lecture in
                            LectureRow(lecture: lecture)
                        }
                    }
                    .padding(.vertical, 4)
                    // List starts a row's separator under its first piece of text, which here
                    // is the status label on the right. Pin it to the left edge instead.
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                }
            }

            Section("Sources") {
                if sources.isEmpty {
                    Text("No files yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(sources) { source in
                    SourceRow(source: source)
                }
            }

            Section("Explanations") {
                if explanations.isEmpty {
                    Text("No explanations yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(explanations) { explanation in
                    NavigationLink {
                        // Plain text for now; Markdown rendering is roadmap step 6.
                        ScrollView {
                            Text(explanation.markdown)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .navigationTitle(explanation.title)
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
    }
}

private struct LectureRow: View {
    let lecture: Lecture

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Lecture \(lecture.number)")
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

private struct SourceRow: View {
    let source: SourceMaterial

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.fileName)
                Text(source.lecture.map { "Lecture \($0.number)" } ?? "Whole project")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
        }
    }

    private var icon: String {
        switch source.kind {
        case .deck: "rectangle.on.rectangle"
        case .notes: "pencil.line"
        case .reference: "book.closed"
        }
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
}
