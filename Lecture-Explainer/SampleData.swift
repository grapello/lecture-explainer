//
//  SampleData.swift
//  Lexia
//

// Everything in this file is wrapped in #if DEBUG, so it is left out of release builds.
#if DEBUG
import Foundation
import SwiftData
import UIKit

/// An in-memory store filled with example courses. Used by the #Preview blocks, and
/// by the app itself when launched with the `--sample-data` argument (handy until
/// the schedule and import screens exist and real data can be entered).
enum SampleData {
    @MainActor static func makeContainer() -> ModelContainer {
        // isStoredInMemoryOnly: nothing is written to disk, so previews start fresh every time.
        let container = try! ModelContainer(
            for: Project.self, Lecture.self, SourceMaterial.self, Explanation.self, ScheduleRule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext

        let qm = Project(name: "Quantum Mechanics for Engineers",
                         instructions: "Explain each slide for an engineering student. Derive every equation step by step and say what each symbol means.")
        context.insert(qm)
        context.insert(Project(name: "Signals and Systems"))

        // Tuesday and Thursday lectures, starting three weeks ago, so the list
        // has past, current and future weeks whatever day you open it.
        let start = calendar.date(byAdding: .weekOfYear, value: -3, to: mondayOfWeek(for: .now, in: calendar))!
        let end = calendar.date(byAdding: .weekOfYear, value: 6, to: start)!
        let tuesday = ScheduleRule(weekday: 3, hour: 10, minute: 15, startDate: start, endDate: end)
        let thursday = ScheduleRule(weekday: 5, hour: 14, minute: 0, startDate: start, endDate: end)
        // Setting the relationship to an object that is already in the context
        // inserts the new object too, so no separate insert call is needed.
        tuesday.project = qm
        thursday.project = qm

        for (index, date) in ScheduleGenerator.dates(for: [tuesday, thursday], calendar: calendar).enumerated() {
            let number = index + 1
            let lecture = Lecture(number: number, date: date)
            lecture.project = qm
            // The first three are explained, the next two have a deck, the rest have nothing yet.
            // (Lecture.status is worked out from these, so it isn't set here.)
            if number <= 5 {
                let name = String(format: "QM4Eng_L%02d_Slides.pdf", number)
                let deck = SourceMaterial(fileName: name, kind: .deck)
                deck.project = qm
                deck.lecture = lecture
                deck.storedPath = writePDF(named: name, folder: qm.folderName, pages: [
                    "Lecture \(number): Introduction",
                    "The wave function ψ(x, t) describes the state of a particle.",
                    "|ψ(x, t)|² is the probability density of finding it at x.",
                ])
            }
            if number <= 3 {
                let explanation = Explanation(markdown: exampleMarkdown(number), title: "Lecture \(number)")
                explanation.lecture = lecture
            }
        }
        let symbols = SourceMaterial(fileName: "Symbols_v1.pdf", kind: .reference)
        symbols.project = qm
        symbols.storedPath = writePDF(named: "Symbols_v1.pdf", folder: qm.folderName,
                                      pages: ["ψ  wave function\nħ  reduced Planck constant\nĤ  Hamiltonian"])

        return container
    }

    /// An explanation shaped like a real one (Markdown with LaTeX formulas), so the
    /// rendering can be seen.
    private static func exampleMarkdown(_ number: Int) -> String {
        #"""
        ## Page 1: Introduction

        Lecture \#(number) is about the **wave function** $\psi(x, t)$, which describes the state of a particle.

        ## Pages 2–3: Probability

        - $|\psi(x, t)|^2$ is the *probability density* of finding the particle at $x$.
        - The total probability is 1:

        $$\int_{-\infty}^{\infty} |\psi(x, t)|^2 \, dx = 1$$

        The state changes in time according to the Schrödinger equation:

        $$i\hbar \frac{\partial \psi}{\partial t} = -\frac{\hbar^2}{2m} \frac{\partial^2 \psi}{\partial x^2} + V(x)\,\psi$$

        | Symbol | Meaning | Unit |
        |---|---|---|
        | $\psi$ | wave function | $\mathrm{m}^{-1/2}$ |
        | $\hbar$ | reduced Planck constant | J·s |

        > Only $|\psi|^2$ can be measured, not $\psi$ itself.
        """#
    }

    /// Draws a small real PDF (one text line per page) into the app's file store, so
    /// the file screens have pages and text to show. Returns its stored path.
    private static func writePDF(named name: String, folder: String, pages: [String]) -> String? {
        let temp = FileManager.default.temporaryDirectory.appending(path: name)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 800, height: 600))
        do {
            try renderer.writePDF(to: temp) { context in
                for text in pages {
                    context.beginPage()
                    (text as NSString).draw(in: CGRect(x: 60, y: 60, width: 680, height: 480),
                                            withAttributes: [.font: UIFont.systemFont(ofSize: 32)])
                }
            }
            return try FileStore.shared.copyIn(temp, projectFolder: folder)
        } catch {
            return nil
        }
    }
}
#endif
