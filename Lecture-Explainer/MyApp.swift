import Foundation
import SwiftData

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
    
    enum LectureStatus: String, Codable { case needsDeck, deckAdded, explained }
    
    var title: String
    var project: Project
    var status: LectureStatus
    var addedAt: Date
    var date: Date
    var number: Int
    
    @Relationship(deleteRule: .cascade, inverse: \Explanations.lecture)
    var explanations: [Explanations] = []
    
    init(number: Int, date: Date, title: String = "") {
           self.number = number
           self.date = date
           self.title = title
           self.addedAt = .now
       }
}


@Model
final class SourceMaterial{
    
    enum SourceKind: String, Codable { case deck, notes, reference }
    
    var fileName: String
    var kind: SourceKind
    var project: Project
    var addedAt: Date
    
    init(fileName: String = "", addedAt: Date) {
        self.fileName = fileName
        self.addedAt = .now
    }
}


@Model
final class Explanations{
    var lecture: Lecture
    var createdAt: Date
    var markdown: String
    var title: String
    
    init(createdAt: Date, markdown: String, title: String = "") {
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
static func parse(_ fileName: String) -> ParsedFileName

static func dates(weekday: Int, hour: Int, minute: Int,
                  from start: Date, to end: Date,
                  skipping skipped: [Date],
                  calendar: Calendar = .current) -> [Date]

static func weekNumber(of date: Date, firstLecture: Date, calendar: Calendar) -> Int
static func isDue(_ date: Date, now: Date) -> Bool
