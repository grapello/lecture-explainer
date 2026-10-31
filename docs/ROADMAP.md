# Roadmap (Lexia)

Build in small steps. Each step should run before moving on. Each numbered section can become a GitHub milestone, and each checkbox an issue.

## Design decisions so far

- **Projects.** The top-level container. Every course-specific thing from the web prototype (start date, schedule, instructions prompt, reference sheet, sources, explanations) belongs to a project.
- **Stored lecture dates.** Lecture dates are real data on each lecture, chosen in a calendar, not computed from a start date. Weeks are derived from the dates.
- **Own API key.** The user pastes an Anthropic API key into settings; it is stored in the Keychain and never in the repo.
- **Local files.** Imported PDFs are copied into app storage so they survive relaunch.
- **Status is computed.** A lecture's status (needs deck / ready / explained) is worked out from its files and explanations, never stored, so it can't go stale.
- **Re-applying a schedule is careful.** Saving the schedule adds missing lectures and removes untouched ones on days no longer scheduled, but never touches lectures moved or added by hand, or that have files or explanations. Lectures are then renumbered (`SchedulePlanner`).
- **Deck numbers win.** A lecture with a deck keeps the number in the deck's file name; the others are numbered by date around it without reusing a deck's number. After a holiday the list shows a gap (no Lecture 6) rather than relabelling the L07 deck as Lecture 6.
- **Two ways to explain.** Third-party apps can't use a Claude.ai plan (Free/Pro/Max) directly; only the API can be called from the app, billed separately. So the app offers both: the API for automatic, batch explanations, and a manual round trip through the Claude app for users who only have a plan. Both use the same prompt.
- **PDFs, not extracted text.** Claude gets each PDF itself and reads every page as text and image, so scanned slides and equations drawn as images come through. This replaced on-device text extraction, which missed those. It costs more per lecture; the reference sheet is prompt-cached.
- **Typeset formulas with bundled KaTeX.** Claude writes LaTeX; explanations are rendered in a web view with KaTeX and marked, bundled with the app so it works offline. Chosen over Unicode maths (no fractions or matrices) and a native Swift renderer (lower quality).
- **Retries, then stop.** A busy API (overloaded, rate limit, server error) is retried after 15 s, 45 s and 120 s, or after the API's `retry-after`. Any other error stops the run, since no credit or an invalid key would make every later lecture fail the same way.
- **Re-explaining asks.** A lecture that already has an explanation asks "replace the old one or keep both?". Replacing deletes the old one only after the new one is saved.
- **Name: Lexia.** Display name and loading screen; the Xcode project, target and Keychain service keep the old name, so nothing breaks and saved keys stay.
- **One drawing for logo and icon.** `LexiaLogo` draws both; a script renders it into the icon PNGs, so the loading screen and the home screen can't drift apart.
- **Try Again continues the stopped run.** It sends the failed lecture and the ones the run hadn't reached, not "all ready lectures", so retrying never spends credit on lectures you didn't ask for.
- **Templates copy the pattern, not the semester.** Instructions and weekly times are copied; dates start today with the old semester's length and are confirmed in the schedule editor, which opens right away. Lectures, files and explanations stay with the old project.
- **API details.** Messages API over URLSession (no Swift SDK exists), API version `2026-10-21`, default model `claude-opus-5-5` at effort `high`, streaming always on, and `fallbacks: "default"` so a declined request is retried on a suitable model server-side.

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

- [x] Pick a weekly schedule: weekday, time, and date range
- [x] Preview generated lecture dates before saving
- [x] Skip dates (holidays, cancelled lectures) with `MultiDatePicker`; add extra lectures one at a time with "Add Lecture" (a date *and time* picker, which `MultiDatePicker` can't do)
- [x] Edit a single lecture's date with a graphical `DatePicker`
- [x] Week list grouped by week, with a highlight on the current one and a "not due yet" state for future lectures
- [ ] Optional: export lectures to the iOS Calendar with EventKit (ask for permission, add the usage description in Info.plist)
- [ ] Optional: local reminders with UserNotifications

## 4. PDF import

- [x] `.fileImporter` for multiple PDFs
- [x] Call `startAccessingSecurityScopedResource()`, then copy each file into app storage under the project
- [x] Assign an unnumbered file to a lecture manually
- [x] Project-wide reference source (for example a symbols sheet), separate from per-lecture decks
- [x] `PDFReader` with PDFKit: page text and page thumbnails
- [x] Remove an imported file

## 5. Claude API

- [x] `KeychainStore` for the API key and a settings screen
- [x] Single request to the Messages API with a hardcoded prompt (Settings > Test Connection)
- [x] Streaming response (URLSession bytes, server-sent events)
- [x] Error handling: invalid key, rate limit, request too large, cancelled
- [x] Stop button via Task cancellation

## 6. Wire it together

- [x] Build the prompt from the project's instructions, the reference source, the lecture's notes and the deck (one `PromptBuilder` used by both modes below)
- [x] **Explain with API** (when a key is saved): one lecture, or "Explain All Ready" for all lectures that have decks and are not yet explained
- [x] **Send to Claude app** (no key needed, uses the user's Claude plan): hand the built prompt to the Claude app via the share sheet, with a Copy Prompt fallback; one lecture at a time
- [x] Paste the answer back: a "Paste Explanation" action on the lecture that saves the clipboard text as its explanation
- [x] Live view while streaming, then save with SwiftData
- [x] Markdown rendering (headings, lists, tables, code)
- [x] Copy text button
- [ ] Not verified yet: a full real explanation through the API (the account had no credit), the Claude app in the share sheet (not installable in the Simulator), and pasting (the Simulator's clipboard stayed empty)

## 6b. Improvements after step 6

- [x] Send the PDFs to Claude instead of extracted text (scanned slides, equations as images)
- [x] Typeset formulas: LaTeX rendered with bundled KaTeX
- [x] Retry when the API is busy
- [x] Re-explaining asks: replace the old explanation or keep both
- [x] Rename to Lexia, with a loading screen

## 7. Polish

- [x] Empty states and clear error messages: a Get Started checklist for new projects; errors that say what to do (no credit, offline, empty clipboard, failed imports); Try Again on a stopped run
- [x] App icon: LexiaLogo rendered by `scripts/render-app-icon.sh`, with Default, Dark and Tinted looks
- [x] Accessibility pass: Dynamic Type layouts for the largest sizes, VoiceOver labels and values, announcements when lectures finish
- [x] Project templates: "Start From" in New Project, "Use as Template" in a project's menu
- [ ] Not verified yet: VoiceOver on a real device (the Simulator has no VoiceOver; labels were checked in code)

## Open questions

- ~~Send the PDF directly to the API or extract text and images locally?~~ **Decided: send the PDFs** (see "PDFs, not extracted text" above). Extracting text on the phone came first, but it lost scanned slides and equations drawn as images.
- Should a project always be a lecture series, or can it be a single document? (If always lectures, the schedule can stay required.)
- Is the optional EventKit export worth it, or is the in-app calendar enough?
- ~~Minimum iOS version~~ **Decided by the Xcode project: iOS 27**, so `MultiDatePicker` (iOS 16) and the newer EventKit access APIs (iOS 17) are both available.
