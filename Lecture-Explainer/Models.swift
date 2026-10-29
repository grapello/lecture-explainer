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

enum SourceKind: String, Codable { case deck, notes, reference }
enum LectureStatus: String, Codable { case needsDeck, deckAdded, explained }

@Model
final class Project {
    var name: String
    var instructions: String
    var createdAt: Date
    
    @Relationship(deleteRule: .cascade, inverse: \Lecture.project)
        var lectures: [Lecture] = []
    
    @Relationship(deleteRule: .cascade, inverse: \SourceMaterial.project)
        var sources: [SourceMaterial] = []
    
    init(name: String, instructions: String = ""){
        self.name = name
        self.instructions = instructions
        self.createdAt = .now
    }
}

@Model
final class Lecture{
        
    var title: String
    var project: Project?
    var status: LectureStatus
    var addedAt: Date
    var date: Date
    var number: Int
    
    @Relationship(deleteRule: .cascade, inverse: \Explanation.lecture)
    var explanations: [Explanation] = []
    
    init(number: Int, date: Date, title: String = "") {
        self.status = .needsDeck
        self.number = number
        self.date = date
        self.title = title
        self.addedAt = .now
       }
}

@Model
final class SourceMaterial{

    var fileName: String
    var kind: SourceKind
    var project: Project?
    var addedAt: Date
    
    init(fileName: String = "", kind: SourceKind) {
        self.fileName = fileName
        self.addedAt = .now
        self.kind = kind
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

enum FileNameParser{
    static func parse(_ fileName: String) -> ParsedFileName{
        var nr: Int?
        let file = fileName.lowercased()
        if let match = fileName.firstMatch(of: /L0*(\d+)/.ignoresCase()){
            // match.1 is the captured digits, as a Substring
            nr = Int(match.1)}
        if let n = nr, n > 99{nr = nil}
        if file.contains("symbol"){
            return ParsedFileName(kind: .reference, lectureNumber: nr, slide: nil)}
        else if file.contains("deriv"){
            return ParsedFileName(kind: .notes, lectureNumber: nr, slide: nil)}
        else{
            return ParsedFileName(kind: .deck, lectureNumber: nr, slide: nil)}
        
    }
}


enum ScheduleGenerator{
    static func dates(weekday: Int, hour: Int, minute: Int,
                      from start: Date, to end: Date,
                      skipping skipped: [Date],
                      calendar: Calendar = .current) -> [Date]{
        fatalError("TODO")
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
    
    static func isDue(date: Date, now: Date) -> Bool{
        fatalError("TODO")
    }

}

