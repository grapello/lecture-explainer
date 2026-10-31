//
//  NewProjectView.swift
//  Lexia
//

import SwiftUI
import SwiftData

/// The sheet for creating a project: a name and the instructions Claude gets,
/// optionally started from an existing project (see ProjectTemplate).
struct NewProjectView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    // Called with the new project, so the list can open it straight away, and
    // whether it was made from a template (its schedule then needs new dates).
    var onCreate: (Project, _ fromTemplate: Bool) -> Void = { _, _ in }

    @State private var template: Project?

    // Typed text lives in @State until Create is tapped, so Cancel leaves no
    // half-made project behind.
    @State private var name = ""
    @State private var instructions = ""
    // Lets code move the keyboard focus: the name field is focused when the sheet opens.
    @FocusState private var nameFocused: Bool

    init(template: Project? = nil, onCreate: @escaping (Project, _ fromTemplate: Bool) -> Void = { _, _ in }) {
        self.onCreate = onCreate
        _template = State(initialValue: template)
        _instructions = State(initialValue: template?.instructions ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        // A sheet gets its own NavigationStack so it can have a title bar with buttons.
        NavigationStack {
            Form {
                if !projects.isEmpty {
                    Section {
                        Picker("Start From", selection: $template) {
                            Text("Blank Project").tag(Project?.none)
                            ForEach(projects) { project in
                                Text(project.name).tag(Optional(project))
                            }
                        }
                        // Picking a template fills in its instructions, unless the user
                        // has already typed their own.
                        .onChange(of: template) { old, new in
                            if instructions.isEmpty || instructions == old?.instructions {
                                instructions = new?.instructions ?? ""
                            }
                        }
                    } footer: {
                        if template != nil {
                            Text("Copies the instructions and the weekly lecture times. You pick the new semester's dates next. Files and explanations are not copied.")
                        }
                    }
                }
                Section("Name") {
                    TextField("e.g. Quantum Mechanics for Engineers", text: $name)
                        .focused($nameFocused)
                }
                Section {
                    TextEditor(text: $instructions)
                        .frame(minHeight: 160)
                } header: {
                    Text("Instructions for Claude")
                } footer: {
                    Text("How explanations for this course should be written: level, language, format. You can change this later.")
                }
            }
            .onAppear { nameFocused = true }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private func create() {
        let project = if let template {
            ProjectTemplate.makeProject(named: trimmedName, instructions: instructions, from: template,
                                        startingOn: .now, calendar: calendar)
        } else {
            Project(name: trimmedName, instructions: instructions)
        }
        context.insert(project)
        dismiss()
        onCreate(project, !project.scheduleRules.isEmpty)
    }
}

#Preview {
    NewProjectView()
        .modelContainer(for: Project.self, inMemory: true)
}
