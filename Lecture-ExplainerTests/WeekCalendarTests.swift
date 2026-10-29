//
//  WeekCalendarTests.swift
//  Lecture-Explainer
//
//  Created by Gabriel Rapello on 29.10.26.
//
import Testing
@testable import Lecture_Explainer
import Foundation

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
cal.firstWeekday = 2

cal.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 10))!

struct WeekCalendarTests{
    @Test func
