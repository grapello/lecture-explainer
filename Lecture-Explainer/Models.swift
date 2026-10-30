//
//  Models.swift
//  Lecture-Explainer
//
//  Created by Gabriel Rapello on 28.10.26.
//

import Foundation
import SwiftData

var calendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current          // or a fixed TimeZone if your dates are zone-agnostic
    cal.firstWeekday = 2             // Monday
    return cal
}()

let formatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "dd.MM.yyyy"
    f.locale = Locale(identifier: "en_US_POSIX")  // stops the user's locale settings from changing how the date is read
    f.timeZone = calendar.timeZone
    return f
}()
func mondayOfWeek(for date: Date, in cal: Calendar) -> Date {
    let day = cal.startOfDay(for: date)
    let weekday = cal.component(.weekday, from: day)   // Sun=1, Mon=2, … Sat=7
    let daysSinceMonday = (weekday + 5) % 7             // Mon→0, Tue→1, … Sun→6
    return cal.date(byAdding: .day, value: -daysSinceMonday, to: day)!
}

enum SourceKind: String, Codable, CaseIterable {
    case deck, notes, reference

    var displayName: String {
        switch self {
        case .deck: "Slide deck"
        case .notes: "Derivation notes"
        case .reference: "Reference"
        }
    }
}
enum LectureStatus: String, Codable { case needsDeck, deckAdded, explained }

/// The top-level container: one course (or lecture series).
/// Everything course-specific hangs off a project, so deleting it removes
/// its lectures, sources, schedule rules and (through the lectures) explanations.
@Model
final class Project {
    var name: String
    var instructions: String
    var createdAt: Date
    // Optional semester range. Optional because a project might be a one-off
    // document rather than a lecture series (see "Open questions" in the roadmap).
    var startDate: Date?
    var endDate: Date?
    // Name of this project's folder for imported PDFs (see FileStore). A random UUID,
    // not the project name, so renaming the project never moves files.
    var folderName: String = UUID().uuidString

    @Relationship(deleteRule: .cascade, inverse: \Lecture.project)
        var lectures: [Lecture] = []

    @Relationship(deleteRule: .cascade, inverse: \SourceMaterial.project)
        var sources: [SourceMaterial] = []

    @Relationship(deleteRule: .cascade, inverse: \ScheduleRule.project)
        var scheduleRules: [ScheduleRule] = []

    init(name: String, instructions: String = ""){
        self.name = name
        self.instructions = instructions
        self.createdAt = .now
    }
}

/// One lecture. Its `date` is stored data, not computed: it starts out as a date
/// from ScheduleGenerator but can be moved by hand, and the week number is always
/// derived from whatever date is stored (WeekCalendar.weekNumber).
@Model
final class Lecture{

    var title: String
    var project: Project?
    var addedAt: Date
    var date: Date
    var number: Int
    // true when the date was set by hand: added as an extra lecture or moved with the
    // date picker. Re-applying the schedule never moves or deletes such a lecture.
    var isManual: Bool = false

    /// Worked out from what the lecture has, instead of stored, so it can never go
    /// stale: importing a deck or saving an explanation updates it automatically.
    var status: LectureStatus {
        if !explanations.isEmpty { return .explained }
        if sources.contains(where: { $0.kind == .deck }) { return .deckAdded }
        return .needsDeck
    }

    @Relationship(deleteRule: .cascade, inverse: \Explanation.lecture)
    var explanations: [Explanation] = []

    // .nullify, not .cascade: a deck still belongs to the project, so deleting
    // the lecture only unlinks its files instead of throwing them away.
    @Relationship(deleteRule: .nullify, inverse: \SourceMaterial.lecture)
    var sources: [SourceMaterial] = []

    init(number: Int, date: Date, title: String = "", isManual: Bool = false) {
        self.number = number
        self.date = date
        self.title = title
        self.isManual = isManual
        self.addedAt = .now
       }
}

/// An imported file: a slide deck, derivation notes, or a project-wide
/// reference such as a symbols sheet (which has no lecture).
@Model
final class SourceMaterial{

    var fileName: String          // the original name, shown in the UI and parsed by FileNameParser
    var kind: SourceKind
    var project: Project?
    var lecture: Lecture?         // nil for project-wide references and not-yet-assigned files
    var slide: Int?               // e.g. derivation notes for slide 22
    // Where the copy lives inside the app's own storage, relative to FileStore's
    // base folder ("<project folder>/<file name>"). Relative, because iOS can change
    // the app container's absolute path between installs and updates.
    var storedPath: String?
    var addedAt: Date

    init(fileName: String = "", kind: SourceKind, slide: Int? = nil) {
        self.fileName = fileName
        self.addedAt = .now
        self.kind = kind
        self.slide = slide
    }
}

/// A repeating lecture slot, such as "every Tuesday at 10:15 from 13 Oct to 2 Feb".
/// A course with two lectures a week has two rules. ScheduleGenerator turns the
/// rules into dates, and those dates are copied onto Lecture objects; after that,
/// moving one lecture by hand never touches the rule.
@Model
final class ScheduleRule{
    var weekday: Int              // Calendar numbering: Sun=1, Mon=2, … Sat=7
    var hour: Int
    var minute: Int
    var startDate: Date
    var endDate: Date
    var skippedDates: [Date] = [] // holidays and cancelled lectures; only the day matters
    var project: Project?

    init(weekday: Int, hour: Int, minute: Int, startDate: Date, endDate: Date, skippedDates: [Date] = []) {
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
        self.startDate = startDate
        self.endDate = endDate
        self.skippedDates = skippedDates
    }
}

@Model
final class Explanation{
    var lecture: Lecture?
    var createdAt: Date
    var markdown: String
    var title: String
    
    init(markdown: String, title: String = "") {
        self.createdAt = .now
        self.markdown = markdown
        self.title = title
    }
}

struct ParsedFileName: Equatable {
    var kind: SourceKind
    var lectureNumber: Int?
    var slide: Int?
}

/// Reads what it can from a file name such as `QM4Eng_L05_Intro.pdf` or
/// `DerivationL02S22.pdf`. Anything it can't read comes back as nil, and the UI
/// lets the user assign the file by hand (roadmap step 4).
enum FileNameParser{
    static func parse(_ fileName: String) -> ParsedFileName{
        var nr: Int?
        var slide: Int?
        let file = fileName.lowercased()
        // "L" + lecture number, optionally followed by "S" + slide number, with or
        // without an underscore between them: L05, L02S22, L02_S22.
        // The slide part is optional, so match.2 is nil when there is none.
        if let match = fileName.firstMatch(of: /L0*(\d+)(?:_?S0*(\d+))?/.ignoresCase()){
            // match.1 is the captured digits, as a Substring
            nr = Int(match.1)
            slide = match.2.flatMap { Int($0) }}
        // Three-digit "lecture numbers" are almost certainly something else
        // (a year, a version); drop the slide too, since it belonged to that match.
        if let n = nr, n > 99{nr = nil; slide = nil}
        if file.contains("symbol"){
            return ParsedFileName(kind: .reference, lectureNumber: nr, slide: slide)}
        else if file.contains("deriv"){
            return ParsedFileName(kind: .notes, lectureNumber: nr, slide: slide)}
        else{
            return ParsedFileName(kind: .deck, lectureNumber: nr, slide: slide)}

    }
}


enum ScheduleGenerator{
    /// Every `weekday` at `hour:minute` between `start` and `end` (both days included),
    /// minus any day listed in `skipped`. Returned in chronological order.
    static func dates(weekday: Int, hour: Int, minute: Int,
                      from start: Date, to end: Date,
                      skipping skipped: [Date],
                      calendar: Calendar = .current) -> [Date]{
        guard (1...7).contains(weekday), start <= end else { return [] }

        let firstDay = calendar.startOfDay(for: start)
        // Midnight *after* the end day, so a lecture on the last day is still included.
        let limit = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end))!
        let slot = DateComponents(hour: hour, minute: minute, weekday: weekday)

        var result: [Date] = []
        // enumerateDates asks the calendar for "the next date matching these components"
        // again and again. It handles daylight saving for us: 10:15 stays 10:15 local
        // time after the clocks change, which adding 7 × 24 hours would not.
        // It only returns dates strictly *after* the starting point, hence the -1 second,
        // so a lecture at midnight on the first day isn't missed.
        calendar.enumerateDates(startingAfter: firstDay.addingTimeInterval(-1),
                                matching: slot,
                                matchingPolicy: .nextTime) { date, _, stop in
            guard let date, date < limit else { stop = true; return }
            // Skipped dates are compared by calendar day, so a holiday entered as
            // 00:00 still removes the 10:15 lecture on that day.
            let isSkipped = skipped.contains { calendar.isDate($0, inSameDayAs: date) }
            if !isSkipped { result.append(date) }
        }
        return result
    }

    /// All dates for a project's rules merged into one sorted list,
    /// e.g. a Tuesday rule and a Thursday rule give Tue, Thu, Tue, Thu, …
    static func dates(for rules: [ScheduleRule], calendar: Calendar = .current) -> [Date]{
        rules.flatMap { rule in
            dates(weekday: rule.weekday, hour: rule.hour, minute: rule.minute,
                  from: rule.startDate, to: rule.endDate,
                  skipping: rule.skippedDates, calendar: calendar)
        }.sorted()
    }
}

enum WeekCalendar{
    
    static func weekNumber(date: Date, firstLecture: Date, calendar: Calendar) -> Int{
        let semMon = mondayOfWeek(for: firstLecture, in: calendar)
        let curMon = mondayOfWeek(for: date, in: calendar)
        let days  = calendar.dateComponents([.day], from: semMon, to: curMon).day!
        let week = (days/7) + 1
        return max(1, week)   // dates before the first lecture count as week 1
    }
    
    /// Groups items into weeks counted from the earliest one (week 1), weeks in order
    /// and items sorted by date inside each week. Used by the week list.
    /// Generic over `T`, with a closure that reads the date, so the same code works on
    /// `Lecture` objects in the app and on plain `Date`s in tests (no SwiftData needed).
    static func groupedByWeek<T>(_ items: [T], date: (T) -> Date,
                                 calendar: Calendar) -> [(week: Int, items: [T])]{
        guard let first = items.map(date).min() else { return [] }
        let byWeek = Dictionary(grouping: items) {
            weekNumber(date: date($0), firstLecture: first, calendar: calendar)
        }
        // Dictionaries have no order, so sort the week numbers before building the result.
        return byWeek.keys.sorted().map { week in
            (week: week, items: byWeek[week]!.sorted { date($0) < date($1) })
        }
    }

    /// A lecture is due once its start time has passed; until then the week list
    /// shows it as "not due yet". `now` is a parameter (defaulting to the real clock)
    /// so tests can pin it to a fixed moment instead of depending on today's date.
    static func isDue(date: Date, now: Date = .now) -> Bool{
        date <= now
    }

}

