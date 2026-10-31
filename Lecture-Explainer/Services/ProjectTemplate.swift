//
//  ProjectTemplate.swift
//  Lexia
//

import Foundation
import SwiftData

/// Starts a new course from an existing one: the next semester of the same lecture,
/// or a similar course. The instructions and the weekly lecture times are copied;
/// lectures, files and explanations are not, since they belong to the old semester.
enum ProjectTemplate {
    /// A new project (not yet inserted) with `template`'s instructions and weekly
    /// slots. The slots get a semester starting on `start`, as long as the old one,
    /// with no skipped days; the schedule editor opens next to adjust them.
    static func makeProject(named name: String, instructions: String, from template: Project,
                            startingOn start: Date, calendar: Calendar) -> Project {
        let project = Project(name: name, instructions: instructions)
        guard let old = template.scheduleRules.first else { return project }

        let firstDay = calendar.startOfDay(for: start)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: old.startDate),
                                           to: calendar.startOfDay(for: old.endDate)).day ?? 0
        let lastDay = calendar.date(byAdding: .day, value: days, to: firstDay)!
        project.startDate = firstDay
        project.endDate = lastDay
        for rule in template.scheduleRules {
            ScheduleRule(weekday: rule.weekday, hour: rule.hour, minute: rule.minute,
                         startDate: firstDay, endDate: lastDay).project = project
        }
        return project
    }
}
