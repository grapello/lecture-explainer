//
//  ScheduleGeneratorTests.swift
//  Lexia
//

import Testing
@testable import Lecture_Explainer
import Foundation

// Uses the Europe/Berlin calendar `cal` from WeekCalendarTests.swift, so the
// results don't depend on the time zone of the machine running the tests.
struct ScheduleGeneratorTests {
    func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // Tuesdays at 10:15 from Tue 13 Oct to Tue 3 Nov 2026
    func tuesdays(skipping skipped: [Date] = []) -> [Date] {
        ScheduleGenerator.dates(weekday: 3, hour: 10, minute: 15,
                                from: day(2026, 10, 13), to: day(2026, 11, 3),
                                skipping: skipped, calendar: cal)
    }

    @Test func includesFirstAndLastDay() {
        let days = tuesdays().map { cal.component(.day, from: $0) }
        #expect(days == [13, 20, 27, 3])
    }

    @Test func keepsLocalTimeAcrossClockChange() {
        // Clocks go back on Sun 25 Oct 2026; the 27 Oct lecture is still at 10:15.
        for date in tuesdays() {
            #expect(cal.component(.hour, from: date) == 10)
            #expect(cal.component(.minute, from: date) == 15)
        }
    }

    @Test func skipsHolidaysByDay() {
        // The holiday is given as midnight; it still removes the 10:15 lecture.
        let days = tuesdays(skipping: [day(2026, 10, 27)]).map { cal.component(.day, from: $0) }
        #expect(days == [13, 20, 3])
    }

    @Test func emptyForBadInput() {
        #expect(ScheduleGenerator.dates(weekday: 3, hour: 10, minute: 15,
                                        from: day(2026, 11, 3), to: day(2026, 10, 13),
                                        skipping: [], calendar: cal).isEmpty)   // end before start
        #expect(ScheduleGenerator.dates(weekday: 9, hour: 10, minute: 15,
                                        from: day(2026, 10, 13), to: day(2026, 11, 3),
                                        skipping: [], calendar: cal).isEmpty)   // no weekday 9
    }

    @Test func twoRulesMergeInOrder() {
        let tue = ScheduleRule(weekday: 3, hour: 10, minute: 15,
                               startDate: day(2026, 10, 12), endDate: day(2026, 10, 25))
        let thu = ScheduleRule(weekday: 5, hour: 14, minute: 0,
                               startDate: day(2026, 10, 12), endDate: day(2026, 10, 25))
        let days = ScheduleGenerator.dates(for: [thu, tue], calendar: cal)
            .map { cal.component(.day, from: $0) }
        #expect(days == [13, 15, 20, 22])
    }
}
