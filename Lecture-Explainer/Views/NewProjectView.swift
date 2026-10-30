//
//  NewProjectView.swift
//  Lecture-Explainer
//

import SwiftUI
import SwiftData

/// The sheet for creating a project: a name and the instructions Claude gets.
struct NewProjectView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    // Called with the new project, so the list can open it straight away.
    var onCreate: (Project) -> Void = { _ in }

    // Typed text lives in @State until Create is tapped, so Cancel leaves no
    // half-made project behind.
    @State private var name = ""
    @State private var instructions = ""
    // Lets code move the keyboard focus: the name field is focused when the sheet opens.
    @FocusState private var nameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        // A sheet gets its own NavigationStack so it can have a title bar with buttons.
        NavigationStack {
            Form {
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
        let project = Project(name: trimmedName, instructions: instructions)
        context.insert(project)
        dismiss()
        onCreate(project)
    }
}

#Preview {
    NewProjectView()
        .modelContainer(for: Project.self, inMemory: true)
}
