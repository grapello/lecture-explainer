//
//  ScheduleEditorView.swift
//  Lexia
//

import SwiftUI
import SwiftData

/// Sheet for a project's weekly schedule: one or more slots (weekday + time),
/// a date range, and days to skip. Shows the resulting lecture dates live, and on
/// Save turns them into lectures through SchedulePlanner.
struct ScheduleEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let project: Project

    /// One weekly slot as it is being edited. Plain values, not ScheduleRule models,
    /// so Cancel throws the edits away without touching the database.
    struct Slot: Identifiable {
        let id = UUID()
        var weekday: Int      // Sun=1, Mon=2, … Sat=7
        var time: Date        // only hour and minute are used
    }

    @State private var slots: [Slot] = []
    @State private var startDate = Date.now
    @State private var endDate = Date.now
    // MultiDatePicker works with DateComponents (year/month/day), not Dates.
    @State private var skippedDays: Set<DateComponents> = []
    @State private var loaded = false

    // Weekdays in Monday-first order, as Calendar numbers them.
    private let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($slots) { $slot in
                        HStack {
                            Picker("Day", selection: $slot.weekday) {
                                ForEach(weekdayOrder, id: \.self) { day in
                                    // weekdaySymbols is indexed from 0 = Sunday, Calendar from 1.
                                    Text(calendar.weekdaySymbols[day - 1]).tag(day)
                                }
                            }
                            .labelsHidden()
                            Spacer()
                            DatePicker("Time", selection: $slot.time, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                    }
                    .onDelete { slots.remove(atOffsets: $0) }
                    Button("Add Lecture Slot", systemImage: "plus") {
                        slots.append(Slot(weekday: 2, time: time(hour: 10, minute: 0)))
                    }
                } header: {
                    Text("Weekly Lectures")
                } footer: {
                    Text("Add a slot for every lecture in a week, e.g. Tuesday 10:15 and Thursday 14:00.")
                }

                Section("Semester") {
                    DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                }

                Section {
                    MultiDatePicker("Skipped days", selection: $skippedDays, in: semesterRange)
                } header: {
                    Text("Skipped Days")
                } footer: {
                    Text("Tap holidays and cancelled lectures. No lecture is created on these days.")
                }

                Section {
                    ForEach(previewDates, id: \.self) { date in
                        Text(date, format: .dateTime.weekday(.abbreviated).day().month().hour().minute())
                    }
                } header: {
                    Text("Preview: \(previewDates.count) lectures")
                } footer: {
                    Text("Lectures you added or moved by hand, and lectures that already have files or explanations, are kept when you save.")
                }
            }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(slots.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    // MARK: - Derived values

    /// The days MultiDatePicker allows: from the first to the last semester day.
    /// A Range needs lower < upper, so it is at least one day long even if the
    /// end date is (briefly) before the start date.
    private var semesterRange: Range<Date> {
        let lower = calendar.startOfDay(for: startDate)
        let afterEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))!
        let minimum = calendar.date(byAdding: .day, value: 1, to: lower)!
        return lower..<max(afterEnd, minimum)
    }

    private var skippedDates: [Date] {
        skippedDays.compactMap { calendar.date(from: DateComponents(year: $0.year, month: $0.month, day: $0.day)) }
    }

    /// The same dates Save will produce, recomputed on every change.
    private var previewDates: [Date] {
        slots.flatMap { slot in
            let (hour, minute) = hourAndMinute(of: slot.time)
            return ScheduleGenerator.dates(weekday: slot.weekday, hour: hour, minute: minute,
                                           from: startDate, to: endDate,
                                           skipping: skippedDates, calendar: calendar)
        }.sorted()
    }

    // MARK: - Loading and saving

    /// Fills the form from the saved rules, or with sensible defaults for a new schedule.
    private func load() {
        guard !loaded else { return }   // onAppear can run again, e.g. after a picker closes
        loaded = true
        let rules = project.scheduleRules
        if let first = rules.first {
            // All rules of a project share one range and one skip list; the editor
            // only lets them differ in weekday and time.
            slots = rules.map { Slot(weekday: $0.weekday, time: time(hour: $0.hour, minute: $0.minute)) }
                .sorted { weekdayOrder.firstIndex(of: $0.weekday)! < weekdayOrder.firstIndex(of: $1.weekday)! }
            startDate = first.startDate
            endDate = first.endDate
            skippedDays = Set(first.skippedDates.map {
                calendar.dateComponents([.calendar, .era, .year, .month, .day], from: $0)
            })
        } else {
            let today = calendar.component(.weekday, from: .now)
            slots = [Slot(weekday: today, time: time(hour: 10, minute: 0))]
            startDate = project.startDate ?? .now
            endDate = project.endDate ?? calendar.date(byAdding: .weekOfYear, value: 14, to: startDate)!
        }
    }

    private func save() {
        // Replace the rules wholesale; they are cheap and only describe the pattern.
        for rule in project.scheduleRules { context.delete(rule) }
        project.scheduleRules = []
        for slot in slots {
            let (hour, minute) = hourAndMinute(of: slot.time)
            let rule = ScheduleRule(weekday: slot.weekday, hour: hour, minute: minute,
                                    startDate: startDate, endDate: endDate, skippedDates: skippedDates)
            rule.project = project
        }
        project.startDate = startDate
        project.endDate = endDate
        // The lectures themselves are updated carefully, not replaced (see SchedulePlanner).
        SchedulePlanner.apply(to: project, context: context, calendar: calendar)
        dismiss()
    }

    // MARK: - Helpers

    private func time(hour: Int, minute: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: .now)!
    }

    private func hourAndMinute(of date: Date) -> (Int, Int) {
        (calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }
}

#Preview {
    let container = SampleData.makeContainer()
    let project = try! container.mainContext.fetch(FetchDescriptor<Project>()).first { !$0.scheduleRules.isEmpty }!
    ScheduleEditorView(project: project)
        .modelContainer(container)
}
