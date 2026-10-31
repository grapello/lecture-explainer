//
//  InstructionsEditorView.swift
//  Lexia
//

import SwiftUI
import SwiftData

/// Full-screen editor for a project's instructions. This replaces the fixed prompt
/// from the web prototype: each course can tell Claude how to explain its slides.
struct InstructionsEditorView: View {
    @Bindable var project: Project

    var body: some View {
        // Bound straight to the model: every keystroke updates the project and
        // SwiftData saves it, so there is no Save button to forget.
        TextEditor(text: $project.instructions)
            .padding(.horizontal)
            .overlay(alignment: .topLeading) {
                // TextEditor has no placeholder of its own, so show one on top while it's empty.
                if project.instructions.isEmpty {
                    Text("e.g. Explain each slide for an engineering student. Derive every equation step by step.")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 21)   // lines up with the editor's own text inset
                        .padding(.top, 8)
                        .allowsHitTesting(false)    // taps go through to the editor underneath
                }
            }
            .navigationTitle("Instructions")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        InstructionsEditorView(project: Project(name: "QM"))
    }
    .modelContainer(for: Project.self, inMemory: true)
}
