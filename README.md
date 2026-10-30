# Lecture Explainer

An iPhone app (Swift / SwiftUI / SwiftData) that turns lecture slide decks into detailed explanations using Claude. It is a native port of a web prototype built for the course *Quantum Mechanics for Engineers*, generalised so any course can be a project.

## What it does

1. **Projects.** One project per course, each with its own instructions for Claude ("explain for an engineering student, derive every step…").
2. **Schedule.** Set the weekly lecture slots (e.g. Tue 10:15 and Thu 14:00), the semester dates and the holidays. The app creates the lectures and groups them by week, highlighting the current week and marking future lectures as "not due yet".
3. **PDF import.** Import decks, derivation notes and a symbols sheet from Files. The lecture number is read from the file name (`QM4Eng_L05_…` → lecture 5) and the file is linked to that lecture automatically.
4. **Claude.** Your own Anthropic API key, stored in the Keychain. Answers stream in word by word, and a request can be stopped.
5. *(Next, roadmap step 6)* One button sends each deck to Claude and saves the explanation.

## Status

Roadmap steps 1–5 are done: data model, projects, schedule and week list, PDF import and reading, and the Claude API client (tested with Settings > Test Connection). Step 6 connects them: building the prompt from a lecture's files and saving the explanation. See [docs/ROADMAP.md](docs/ROADMAP.md).

## Requirements

- A Mac with Xcode, and the iOS 27 SDK (the project's deployment target)
- An iPhone, or the Xcode iOS Simulator
- An Apple ID (free) to run on your own device. Apps signed this way expire after 7 days and need rebuilding.
- An Anthropic API key (pay-per-use, separate from a Claude subscription) for the Claude features

## Getting started

1. Clone the repo and open `Lecture-Explainer.xcodeproj`.
2. Pick an iPhone simulator and press Run (⌘R).
3. **Try it with sample data:** Product > Scheme > Edit Scheme > Run > Arguments, add `--sample-data`. The app then starts with an in-memory example course (12 lectures, some decks and explanations, real little PDFs). Nothing is saved; remove the argument to use your real data. Only works in Debug builds.
4. Run the tests with ⌘U (no API key or network needed).
5. For Claude: Settings (gear icon) > paste your API key > Save > Send Test Request.

### Getting PDFs into the Simulator

Drag a PDF from Finder onto the Simulator window and save it to Files ("On My iPhone") from the sheet that opens. If your Xcode version handles the drop differently, open a PDF in Safari inside the Simulator and use Share > Save to Files. Then use + > Import PDFs in a project.

## How the app is built

### Project layout

```
Lecture-Explainer/
  MyApp.swift            App entry; creates the SwiftData store (or sample data)
  ContentView.swift      Root view → ProjectListView
  Models.swift           SwiftData models + small pure logic:
                         FileNameParser, ScheduleGenerator, WeekCalendar
  SampleData.swift       Debug-only example data for previews and --sample-data
  Utilities/
    SchedulePlanner.swift  Applies a schedule to existing lectures; renumbering
  Services/
    FileStore.swift        Where imported PDFs live on disk
    SourceImporter.swift   Picked files → SourceMaterial records
    PDFReader.swift        PDFKit: page count, page text, thumbnails
    KeychainStore.swift    API key in the Keychain
    ClaudeClient.swift     Messages API request, SSE stream parsing, errors
  Views/
    ProjectListView        Projects: create, rename, delete; Settings link
    NewProjectView         Sheet: name + instructions
    ProjectDetailView      Instructions, schedule, weeks, sources, explanations
    InstructionsEditorView Full-screen instructions editor
    ScheduleEditorView     Weekly slots, semester, skipped days, live preview
    LectureDetailView      One lecture (+ AddLectureView, ExplanationView)
    SourceDetailView       One file: kind, lecture, page thumbnails, text
    SettingsView           API key, model, effort, test request
Lecture-ExplainerTests/   Swift Testing unit tests (one file per area)
docs/ROADMAP.md
```

### Data model (SwiftData)

| Model | Holds | Relationships |
|---|---|---|
| `Project` | name, instructions, semester dates, `folderName` for its files | lectures, sources, scheduleRules: all deleted with the project |
| `ScheduleRule` | weekday, time, date range, skipped days | belongs to a project |
| `Lecture` | number, date, title, `isManual` | explanations (deleted with it), sources (unlinked, kept) |
| `SourceMaterial` | file name, kind (deck / notes / reference), slide, `storedPath` | project, optional lecture |
| `Explanation` | markdown, title, date | belongs to a lecture |

`Lecture.status` (needs deck / ready / explained) is **computed** from the lecture's files and explanations rather than stored, so importing a deck or saving an explanation updates it with no extra code.

### Dates and weeks

- `ScheduleGenerator` turns a rule into dates with `Calendar.enumerateDates`, asking for "the next Tuesday at 10:15" again and again. That keeps the local time right across daylight-saving changes, which adding 7 × 24 h would not. Skipped days are matched by calendar day.
- `SchedulePlanner` applies a saved schedule to lectures that may already exist. It adds missing days and removes untouched lectures on days no longer scheduled. It keeps anything moved or added by hand (`isManual`) or that has files or explanations. Then it renumbers lectures 1, 2, 3… by date.
- `WeekCalendar` gives week numbers counted from the Monday of the first lecture's week (dates before it count as week 1), groups lectures by week, and decides "due" (start time has passed).

All date logic takes a `Calendar` parameter, so tests use a fixed Europe/Berlin calendar and give the same result on any machine.

### Files

- The Files picker returns *security-scoped* URLs: the app may read them only between `startAccessingSecurityScopedResource()` and `stop…`. `SourceImporter` copies each file into `Application Support/Sources/<project folder>/` during that window, so decks survive relaunches and moving the original.
- `SourceMaterial.storedPath` is relative (`<folder>/<file>`), because iOS can change the app container's absolute path between installs.
- Importing a file with an existing name replaces it instead of duplicating it. Deleting a project or file also deletes the copies on disk.
- `PDFReader` extracts text **on the device** with PDFKit, and that text is what will be sent to Claude (roadmap decision). A file's Text tab shows exactly that. Equations drawn as images and scanned slides give little or no text.

### Claude API

There is no official Anthropic SDK for Swift, so `ClaudeClient` calls the Messages API directly:

- `POST https://api.anthropic.com/v1/messages` with headers `x-api-key`, `anthropic-version: 2026-10-21` and `content-type: application/json`.
- Body: `model`, `max_tokens`, `stream: true`, `system` (the project's instructions), `messages`, and `output_config.effort`.
- Default model `claude-opus-5-5` at effort `high`. Opus 5.5 always thinks before answering, and effort is how much; `high` suits derivations. Sonnet 5.5 and Haiku 5.5 can be chosen in Settings to save cost.
- `fallbacks: "default"` (beta header `server-side-fallback-2026-07-01`): if the model declines a request, the API re-runs it on a suitable other model inside the same call. Haiku doesn't support this, so the field is left out for Haiku.
- **Streaming:** the reply arrives as Server-Sent Events. `ClaudeStreamEvent.parse` reads each `data:` line: `text_delta` pieces are shown, thinking deltas and pings are skipped, and the `message_delta` stop reason and `error` events are checked. The client exposes this as an `AsyncThrowingStream<String, Error>`.
- **Stopping:** cancel the Task that loops over the stream; that cancels the network request.
- **Errors** become `ClaudeError` with a readable message: invalid key (401), billing (402), permission (403), model not found (404), too large (413), rate limited (429, with `retry-after`), server (500), overloaded (529), declined (`refusal`).

### API key handling

The app never contains a key. You paste your own key into Settings, and it is stored in the iOS Keychain (`KeychainStore`) with `…AfterFirstUnlockThisDeviceOnly`: encrypted, not synced to iCloud, and not restored to another device. Do not commit keys, `.xcconfig` secrets or `.env` files; `.gitignore` excludes common secret file names. It also excludes `*.pdf`, because course slides may be copyrighted. The tests generate their own PDFs.

## Tests

`Lecture-ExplainerTests/` uses Swift Testing (`@Test`, `#expect`). Areas covered:

- file-name parsing, including bad names
- week numbers, due status and grouping
- schedule generation (daylight saving, holidays) and planning (manual lectures, renumbering)
- SwiftData delete rules
- import, storage and removal with real generated PDFs
- PDF text and thumbnails
- the Keychain
- the Claude client: request building, SSE parsing, and error mapping against a fake server (`MockURLProtocol`), so no API key or network is used

## Build caches in the project folder

If folders like `ModuleCache.noindex/`, `SDKExplicitPrecompiledModules/` or `Lecture-Explainer-<random>/` appear here, a build used this folder as its DerivedData location (for example `xcodebuild -derivedDataPath .`). They are ignored by git and safe to delete; Xcode recreates what it needs in its normal DerivedData folder.

## License

Not yet chosen. Personal project.
