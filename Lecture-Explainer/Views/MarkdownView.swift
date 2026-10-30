//
//  MarkdownView.swift
//  Lecture-Explainer
//

import SwiftUI

/// Draws Markdown: MarkdownParser splits it into blocks, and each block gets its
/// own view. Used for saved explanations and for the answer while it streams in,
/// so it is cheap enough to redraw on every new piece of text.
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Blocks have no identity of their own; their position is a stable
            // enough id, as streaming only ever adds blocks at the end.
            ForEach(Array(MarkdownParser.parse(markdown).enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

/// Inline Markdown (**bold**, *italic*, `code`, links) as styled text. Text only
/// renders inline syntax, which is exactly what is left inside a block. Falls back
/// to the plain string if the Markdown can't be read.
private func inline(_ text: String) -> Text {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    if let attributed = try? AttributedString(markdown: text, options: options) {
        return Text(attributed)
    }
    return Text(text)
}

private struct BlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, level <= 2 ? 8 : 4)

        case .paragraph(let text):
            inline(text)

        case .list(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.number ?? "•")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        inline(item.text)
                    }
                    .padding(.leading, CGFloat(item.level) * 18)
                }
            }

        case .code(let code):
            // Long lines scroll sideways instead of wrapping, as in a code editor.
            ScrollsWhenWide {
                Text(code)
                    .font(.callout.monospaced())
                    .padding(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))

        case .table(let header, let rows):
            TableBlock(header: header, rows: rows)

        case .quote(let text):
            inline(text)
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.tertiary).frame(width: 3)
                }

        case .rule:
            Divider()
        }
    }
}

/// Shows its content as it is when it fits the width, and in a sideways-scrolling
/// view only when it is wider. ViewThatFits tries the options in order and takes
/// the first that fits, so narrow content doesn't swallow horizontal swipes.
private struct ScrollsWhenWide<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            content
            ScrollView(.horizontal) { content }
        }
    }
}

/// A Markdown table as a Grid (columns line up across rows). It scrolls sideways
/// when it is wider than the screen, which tables with many columns often are.
private struct TableBlock: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        ScrollsWhenWide {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        inline(cell).bold()
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        // A short row gets empty cells, so its columns still line up.
                        ForEach(0..<header.count, id: \.self) { column in
                            inline(column < row.count ? row[column] : "")
                        }
                    }
                }
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 8))
    }
}

#Preview {
    ScrollView {
        MarkdownView(markdown: """
        ## Page 1: The wave function

        The state of a particle is described by **ψ(x, t)**, a complex function.

        - |ψ(x, t)|² is the *probability density*
        - ψ itself is not measurable
          (only |ψ|² is)

        1. Normalise: ∫ |ψ|² dx = 1
        2. Evolve with the Schrödinger equation

        | Symbol | Meaning | Unit |
        |---|---|---|
        | ħ | reduced Planck constant | J·s |
        | Ĥ | Hamiltonian | J |

        > iħ ∂ψ/∂t = Ĥψ

        ```
        E = ħω
        ```
        """)
        .padding()
    }
}
