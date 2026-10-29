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
}
