//
//  LectureDetailView.swift
//  Lecture-Explainer
//

import SwiftUI
import SwiftData

/// One lecture: its date (editable with a calendar), title, files and explanations.
struct LectureDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var lecture: Lecture
    @State private var confirmingDelete = false

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

            Section("Explanations") {
                if lecture.explanations.isEmpty {
                    Text("Not explained yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(lecture.explanations) { explanation in
                    NavigationLink(explanation.title.isEmpty ? "Untitled" : explanation.title) {
                        ExplanationView(explanation: explanation)
                    }
                }
            }

            Section {
                Button("Delete Lecture", role: .destructive) { confirmingDelete = true }
            }
        }
        .navigationTitle("Lecture \(lecture.number)")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete Lecture \(lecture.number)?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete Lecture", role: .destructive) { delete() }
        } message: {
            Text("Its explanations are deleted. Its files stay in the project, unassigned.")
        }
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

/// An explanation's text. Plain for now; Markdown rendering is roadmap step 6.
struct ExplanationView: View {
    let explanation: Explanation

    var body: some View {
        ScrollView {
            Text(explanation.markdown)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(explanation.title)
    }
}

#Preview {
    let container = SampleData.makeContainer()
    let lecture = try! container.mainContext.fetch(FetchDescriptor<Lecture>(sortBy: [SortDescriptor(\.number)])).first!
    NavigationStack {
        LectureDetailView(lecture: lecture)
    }
    .modelContainer(container)
}
