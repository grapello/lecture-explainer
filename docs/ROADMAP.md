# Roadmap

Build in small steps. Each step should run before moving on. Each numbered section can become a GitHub milestone, and each checkbox an issue.

## Design decisions so far

- **Projects.** The top-level container. Every course-specific thing from the web prototype (start date, schedule, instructions prompt, reference sheet, sources, explanations) belongs to a project.
- **Stored lecture dates.** Lecture dates are real data on each lecture, chosen in a calendar, not computed from a start date. Weeks are derived from the dates.
- **Own API key.** The user pastes an Anthropic API key into settings; it is stored in the Keychain and never in the repo.
- **Local files.** Imported PDFs are copied into app storage so they survive relaunch.

## Data model (SwiftData)

- `Project`: name, instructions prompt, optional date range, created date
- `ScheduleRule` (optional): weekday, time, start and end date, skipped dates (holidays), used to generate lectures
- `Lecture`: belongs to a project; number, date, status, title (the date can be edited by hand)
- `SourceMaterial`: belongs to a project (and optionally a lecture); kind (deck, derivation notes, reference), file name, optional slide number, stored file (`@Attribute(.externalStorage)` or a file path)
- `Explanation`: belongs to a lecture; markdown, explained date

Use `@Relationship(deleteRule: .cascade)` so deleting a project removes its lectures, sources and explanations.

## 1. Model layer and logic (no UI)

- [x] SwiftData models: `Project`, `Lecture`, `SourceMaterial`, `Explanation`
- [x] `FileNameParser`: extract the lecture number from names like `QM4Eng_L05_...pdf`; classify as deck, derivation notes, or reference
- [x] `WeekCalendar`: derive the week number and "due" status from a lecture's date
- [x] `ScheduleGenerator`: turn a `ScheduleRule` (weekday, time, range, skipped dates) into a list of lecture dates
- [x] Unit tests for all of the above, including bad file names, holidays, and lectures moved by hand

## 2. Projects and navigation

- [x] Projects list screen: create, rename, delete (with confirmation)
- [x] Create-project flow: name and instructions prompt
- [x] Project detail screen with sections for Weeks, Sources, Explanations
- [x] Editable per-project instructions (replaces the fixed prompt from the prototype)
- [x] Light and dark mode check

## 3. Calendar and lecture dates

- [ ] Pick a weekly schedule: weekday, time, and date range
- [ ] Preview generated lecture dates before saving
- [ ] Skip dates (holidays, cancelled lectures) and add extra ones with `MultiDatePicker`
- [ ] Edit a single lecture's date with a graphical `DatePicker`
- [ ] Week list grouped by week, with a highlight on the current one and a "not due yet" state for future lectures
- [ ] Optional: export lectures to the iOS Calendar with EventKit (ask for permission, add the usage description in Info.plist)
- [ ] Optional: local reminders with UserNotifications

## 4. PDF import

- [ ] `.fileImporter` for multiple PDFs
- [ ] Call `startAccessingSecurityScopedResource()`, then copy each file into app storage under the project
- [ ] Assign an unnumbered file to a lecture manually
- [ ] Project-wide reference source (for example a symbols sheet), separate from per-lecture decks
- [ ] `PDFReader` with PDFKit: page text and page thumbnails
- [ ] Remove an imported file

## 5. Claude API

- [ ] `KeychainStore` for the API key and a settings screen
- [ ] Single request to the Messages API with a hardcoded prompt
- [ ] Streaming response (URLSession bytes, server-sent events)
- [ ] Error handling: invalid key, rate limit, request too large, cancelled
- [ ] Stop button via Task cancellation

## 6. Wire it together

- [ ] Build the prompt from the project's instructions, the reference source, the lecture's notes and the deck
- [ ] Run all lectures that have decks and are not yet explained
- [ ] Live view while streaming, then save with SwiftData
- [ ] Markdown rendering (headings, tables, code)
- [ ] Copy text button

## 7. Polish

- [ ] Empty states and clear error messages
- [ ] App icon and launch screen
- [ ] Accessibility pass (Dynamic Type, VoiceOver labels)
- [ ] Optional: project templates (duplicate a project's instructions and schedule for a new course)

## Open questions

- Send the PDF directly to the API or extract text and images locally? Check current API docs for limits.
- Should a project always be a lecture series, or can it be a single document? (If always lectures, the schedule can stay required.)
- Is the optional EventKit export worth it, or is the in-app calendar enough?
- Minimum iOS version: `MultiDatePicker` needs iOS 16, and the newer EventKit access APIs need iOS 17.
