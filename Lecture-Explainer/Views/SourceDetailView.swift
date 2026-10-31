//
//  SourceDetailView.swift
//  Lexia
//

import SwiftUI
import SwiftData

/// One imported file: what kind it is, which lecture it belongs to, and its pages,
/// either as thumbnails or as the text the app extracted from them.
struct SourceDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var source: SourceMaterial

    private enum Tab { case pages, text }
    @State private var tab = Tab.pages
    @State private var confirmingDelete = false

    /// Opened once per screen. nil when the stored file is missing.
    @State private var reader: PDFReader?

    private var lectures: [Lecture] {
        (source.project?.lectures ?? []).sorted { $0.number < $1.number }
    }

    var body: some View {
        List {
            Section {
                Picker("Kind", selection: $source.kind) {
                    ForEach(SourceKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                // A reference (e.g. a symbols sheet) belongs to the whole project.
                .onChange(of: source.kind) { _, kind in
                    if kind == .reference { source.lecture = nil }
                }
                // Manual assignment for files whose name has no lecture number.
                // The tags are Optional<Lecture> so that "None" (nil) can be selected.
                Picker("Lecture", selection: $source.lecture) {
                    Text("None").tag(Lecture?.none)
                    ForEach(lectures) { lecture in
                        Text("Lecture \(lecture.number)").tag(Optional(lecture))
                    }
                }
                .disabled(source.kind == .reference)
            } footer: {
                if source.kind == .reference {
                    Text("References are sent with every lecture of this project.")
                }
            }

            if let reader {
                Section {
                    Picker("Show", selection: $tab) {
                        Text("Pages").tag(Tab.pages)
                        Text("Text").tag(Tab.text)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    switch tab {
                    case .pages:
                        PageGrid(reader: reader)
                    case .text:
                        // The text PDFKit finds in the file. Claude gets the PDF itself
                        // (text and page images), so it also sees what isn't listed here.
                        Text(reader.fullText())
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("\(reader.pageCount) page\(reader.pageCount == 1 ? "" : "s")")
                }
            } else {
                Section {
                    Text("The file couldn't be opened. Import it again.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Remove File", role: .destructive) { confirmingDelete = true }
            }
        }
        .navigationTitle(source.fileName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if reader == nil, let path = source.storedPath {
                reader = PDFReader(url: FileStore.shared.url(for: path))
            }
        }
        .confirmationDialog("Remove \(source.fileName)?", isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Remove File", role: .destructive) {
                SourceImporter.remove(source, context: context)
                dismiss()
            }
        } message: {
            Text("The app's copy is deleted. The original in Files is not touched.")
        }
    }
}

/// Page thumbnails in a grid. Each thumbnail is rendered when its cell first
/// appears (LazyVGrid + .task), so a 60-page deck doesn't render 60 images up front.
private struct PageGrid: View {
    let reader: PDFReader

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
            ForEach(0..<reader.pageCount, id: \.self) { index in
                PageThumbnail(reader: reader, index: index)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct PageThumbnail: View {
    let reader: PDFReader
    let index: Int
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Rectangle().fill(.quaternary).aspectRatio(4 / 3, contentMode: .fit)
                }
            }
            .border(.separator)
            Text("\(index + 1)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        // One VoiceOver stop per page, read as "Page 3" rather than just "3".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1)")
        .accessibilityAddTraits(.isImage)
        .task { image = reader.thumbnail(ofPage: index, width: 280) }
    }
}

/// A file in a list: icon by kind, name, and where it belongs.
struct SourceRow: View {
    let source: SourceMaterial

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.fileName)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(isUnassigned ? .orange : .secondary)
            }
        } icon: {
            Image(systemName: icon)
        }
    }

    private var isUnassigned: Bool { source.lecture == nil && source.kind != .reference }

    private var caption: String {
        if source.kind == .reference { return "Whole project" }
        guard let lecture = source.lecture else { return "Not assigned to a lecture" }
        let slide = source.slide.map { " · slide \($0)" } ?? ""
        return "Lecture \(lecture.number)\(slide)"
    }

    private var icon: String {
        switch source.kind {
        case .deck: "rectangle.on.rectangle"
        case .notes: "pencil.line"
        case .reference: "book.closed"
        }
    }
}
