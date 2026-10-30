//
//  SchedulePlanner.swift
//  Lecture-Explainer
//

import Foundation
import SwiftData

/// Applies a schedule to a project that may already have lectures.
///
/// Saving a schedule is not "delete everything and regenerate": lectures can already
/// have decks and explanations attached, or have been moved by hand. So the planner
/// compares what the schedule produces with what exists, day by day:
///
/// - a generated day with no lecture yet          → add a lecture
/// - a generated day that already has a lecture   → keep it (and update its time
///                                                   if the slot's time changed)
/// - an existing lecture on a day the schedule no longer produces
///     - moved or added by hand, or has files/explanations → keep it
///     - otherwise (an untouched generated lecture)        → remove it
///
/// Afterwards all lectures are renumbered 1, 2, 3, … in date order.
enum SchedulePlanner {
    /// The parts of an existing lecture the plan depends on. A plain struct rather
    /// than `Lecture`, so the planning logic can be tested without SwiftData.
    struct Existing {
        var date: Date
        var isManual: Bool
        var hasContent: Bool
    }

    struct Plan: Equatable {
        var datesToAdd: [Date] = []
        /// Indices into the `existing` array that should be deleted.
        var indicesToRemove: [Int] = []
        /// Index into `existing` → its new date (same day, new time).
        var datesToMove: [Int: Date] = [:]
    }

    static func plan(existing: [Existing], generated: [Date], calendar: Calendar) -> Plan {
        var plan = Plan()
        for date in generated {
            if let index = existing.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
                // Hand-set times win; only lectures the schedule created follow a time change.
                if !existing[index].isManual && existing[index].date != date {
                    plan.datesToMove[index] = date
                }
            } else {
                plan.datesToAdd.append(date)
            }
        }
        for (index, lecture) in existing.enumerated() {
            let stillScheduled = generated.contains { calendar.isDate($0, inSameDayAs: lecture.date) }
            if !stillScheduled && !lecture.isManual && !lecture.hasContent {
                plan.indicesToRemove.append(index)
            }
        }
        return plan
    }

    /// Generates the dates for the project's rules and brings its lectures in line.
    static func apply(to project: Project, context: ModelContext, calendar: Calendar) {
        let generated = ScheduleGenerator.dates(for: project.scheduleRules, calendar: calendar)
        let lectures = project.lectures
        let existing = lectures.map {
            Existing(date: $0.date, isManual: $0.isManual,
                     hasContent: !$0.sources.isEmpty || !$0.explanations.isEmpty)
        }
        let plan = plan(existing: existing, generated: generated, calendar: calendar)

        for (index, date) in plan.datesToMove {
            lectures[index].date = date
        }
        for index in plan.indicesToRemove {
            context.delete(lectures[index])
        }
        for date in plan.datesToAdd {
            let lecture = Lecture(number: 0, date: date)   // numbered below
            lecture.project = project
        }
        renumber(project)
    }

    /// Numbers the project's lectures 1, 2, 3, … by date. Called after anything that
    /// adds, removes or moves a lecture, so "Lecture 5" is always the fifth one.
    static func renumber(_ project: Project) {
        // isDeleted: a lecture deleted a moment ago can still be in the array until save.
        let ordered = project.lectures.filter { !$0.isDeleted }.sorted { $0.date < $1.date }
        for (index, lecture) in ordered.enumerated() where lecture.number != index + 1 {
            lecture.number = index + 1
        }
    }
}
