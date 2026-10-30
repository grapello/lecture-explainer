//
//  WeekCalendarTests.swift
//  Lecture-Explainer
//
//  Created by Gabriel Rapello on 29.10.26.
//
import Testing
@testable import Lecture_Explainer
import Foundation

let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    c.firstWeekday = 2
    return c
}()

struct WeekCalendarTests{
    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: 10))!
    }
    @Test(arguments: [
        (2026, 10, 14, 1),   // Wednesday of week 1
        (2026, 10, 18, 1),   // Sunday: still week 1
        (2026, 10, 19, 2),   // next Monday
        (2026, 11, 2, 4),    // after the clocks change
        (2027, 1, 4, 13),    // after New Year
        (2026, 10, 7, 1),    // before the start
    ])
    func weekNumberCountsFromFirstLecture(year: Int, month: Int, day: Int, expected: Int) {
        let first = date(2026, 10, 12)
        let result = WeekCalendar.weekNumber(date: date(year, month, day),
                                             firstLecture: first, calendar: cal)
        #expect(result == expected)
    }

    @Test func isDueOnlyOnceTheLectureHasStarted() {
        let lecture = date(2026, 10, 14)                       // 10:00
        #expect(!WeekCalendar.isDue(date: lecture, now: date(2026, 10, 13)))
        #expect(WeekCalendar.isDue(date: lecture, now: lecture))  // exactly at the start
        #expect(WeekCalendar.isDue(date: lecture, now: date(2026, 10, 20)))
    }

    // A lecture moved by hand: the week and due state follow the stored date,
    // not the schedule it was generated from.
    @Test func movedLectureFollowsItsNewDate() {
        let first = date(2026, 10, 12)
        let lecture = Lecture(number: 2, date: date(2026, 10, 16))   // Friday, week 1
        lecture.date = date(2026, 10, 19)                             // moved to Monday
        #expect(WeekCalendar.weekNumber(date: lecture.date, firstLecture: first, calendar: cal) == 2)
        #expect(!WeekCalendar.isDue(date: lecture.date, now: date(2026, 10, 17)))
    }

    @Test func groupsByWeekInOrder() {
        // Given out of order on purpose; Thu 30 Oct is week 3, there is no lecture in between.
        let dates = [date(2026, 10, 20), date(2026, 10, 15), date(2026, 10, 30), date(2026, 10, 13)]
        let groups = WeekCalendar.groupedByWeek(dates, date: { $0 }, calendar: cal)
        #expect(groups.map(\.week) == [1, 2, 3])
        #expect(groups[0].items == [date(2026, 10, 13), date(2026, 10, 15)])
        #expect(WeekCalendar.groupedByWeek([Date](), date: { $0 }, calendar: cal).isEmpty)
    }
}
