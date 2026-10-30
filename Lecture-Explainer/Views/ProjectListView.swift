//
//  ProjectListView.swift
//  Lecture-Explainer
//

import SwiftUI
import SwiftData

/// The first screen: all projects, newest first. Create with +, rename and delete
/// by swiping a row or long-pressing it.
struct ProjectListView: View {
    @Environment(\.modelContext) private var context
    // @Query fetches from SwiftData and keeps the list up to date by itself:
    // insert, rename or delete a project anywhere and this view redraws.
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]

    // The navigation path, held here so code can push a screen
    // (opening a project right after creating it) or pop one (after deleting it).
    @State private var path: [Project] = []
    @State private var showingNewProject = false
    // The project the rename alert / delete dialog is about. nil means "not showing".
    @State private var projectToRename: Project?
    @State private var renameText = ""
    @State private var projectToDelete: Project?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(projects) { project in
                    // A value-based link: it pushes `project`, and navigationDestination
                    // below decides which screen shows it.
                    NavigationLink(value: project) {
                        ProjectRow(project: project)
                    }
                    .swipeActions {
                        // A plain button tinted red rather than role: .destructive, because the
                        // destructive role animates the row away before the user has confirmed.
                        Button("Delete", systemImage: "trash") { projectToDelete = project }
                            .tint(.red)
                        Button("Rename", systemImage: "pencil") { startRenaming(project) }
                    }
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { startRenaming(project) }
                        Button("Delete", systemImage: "trash", role: .destructive) { projectToDelete = project }
                    }
                }
            }
            .overlay {
                if projects.isEmpty {
                    ContentUnavailableView("No Projects", systemImage: "books.vertical",
                                           description: Text("Tap + to add a course."))
                }
            }
            .navigationTitle("Projects")
            .navigationDestination(for: Project.self) { project in
                ProjectDetailView(project: project)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Project", systemImage: "plus") { showingNewProject = true }
                }
            }
            .sheet(isPresented: $showingNewProject) {
                NewProjectView { project in path = [project] }
            }
            .alert("Rename Project", isPresented: isShowing($projectToRename)) {
                TextField("Name", text: $renameText)
                Button("Save") { saveRename() }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete Project?", isPresented: isShowing($projectToDelete),
                                titleVisibility: .visible, presenting: projectToDelete) { project in
                Button("Delete “\(project.name)”", role: .destructive) { delete(project) }
            } message: { _ in
                Text("Its lectures, files and explanations are deleted too. This can't be undone.")
            }
        }
    }

    private func startRenaming(_ project: Project) {
        renameText = project.name
        projectToRename = project
    }

    private func saveRename() {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty name is ignored rather than saved; the old name stays.
        guard let project = projectToRename, !name.isEmpty else { return }
        project.name = name   // SwiftData saves model changes automatically
    }

    private func delete(_ project: Project) {
        path.removeAll { $0 == project }   // don't leave a deleted project on screen
        // The cascade rules on Project remove its lectures, sources, rules and explanations.
        // The PDF copies on disk are separate files SwiftData doesn't know about.
        FileStore.shared.removeFolder(project.folderName)
        context.delete(project)
    }

    /// Turns "an optional is set" into the Bool binding that .alert and
    /// .confirmationDialog want. Dismissing the dialog sets the optional back to nil.
    private func isShowing<T>(_ item: Binding<T?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } })
    }
}

private struct ProjectRow: View {
    let project: Project

    var body: some View {
        let explained = project.lectures.filter { $0.status == .explained }.count
        VStack(alignment: .leading, spacing: 2) {
            Text(project.name)
                .font(.headline)
            Text("\(project.lectures.count) lectures · \(explained) explained")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ProjectListView()
        .modelContainer(SampleData.makeContainer())
        .environment(Explainer())
}

#Preview("Empty") {
    ProjectListView()
        .modelContainer(for: Project.self, inMemory: true)
        .environment(Explainer())
}
