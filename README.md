# Lecture Explainer

An iPhone app (Swift / SwiftUI / SwiftData) that turns lecture slide decks into detailed explanations using Claude. It is a native port of a web prototype built for the course *Quantum Mechanics for Engineers*, generalised so any course can be a project.

## What it does

1. **Projects.** One project per course, each with its own instructions for Claude ("explain for an engineering student, derive every step…").
2. **Schedule.** Set the weekly lecture slots (e.g. Tue 10:15 and Thu 14:00), the semester dates and the holidays. The app creates the lectures and groups them by week, highlighting the current week and marking future lectures as "not due yet".
3. **PDF import.** Import decks, derivation notes and a symbols sheet from Files. The lecture number is read from the file name (`QM4Eng_L05_…` → lecture 5) and the file is linked to that lecture automatically.
4. **Explain.** Two ways, using the same prompt (the project's instructions, the symbols sheet, the lecture's deck and notes):
   - **With the API:** your own Anthropic API key, stored in the Keychain. "Explain with Claude" on a lecture, or ✨ "Explain All Ready" on a project for every lecture with a deck and no explanation yet. The answer streams in word by word, can be stopped, and is saved when it is complete.
   - **With the Claude app:** no key needed, runs on your Claude plan. "Send to Claude App" (or "Copy Prompt"), let Claude answer there, copy the answer, then "Paste Explanation" on the lecture.
5. **Read.** Explanations are rendered from Markdown (headings, lists, tables, code) and can be copied.

## Status

Roadmap steps 1–6 are done: data model, projects, schedule and week list, PDF import and reading, the Claude API client, and explaining lectures (API or Claude app) with rendered explanations. Step 7 is polish: empty states, app icon, accessibility. See [docs/ROADMAP.md](docs/ROADMAP.md).

## Requirements

- A Mac with Xcode, and the iOS 27 SDK (the project's deployment target)
- An iPhone, or the Xcode iOS Simulator
- An Apple ID (free) to run on your own device. Apps signed this way expire after 7 days and need rebuilding.
- For explaining lectures, either an Anthropic API key (pay-per-use API credit, separate from a Claude subscription) or the Claude app with a Claude plan

## Getting started

1. Clone the repo and open `Lecture-Explainer.xcodeproj`.
2. Pick an iPhone simulator and press Run (⌘R).
3. **Try it with sample data:** Product > Scheme > Edit Scheme > Run > Arguments, add `--sample-data`. The app then starts with an in-memory example course (12 lectures, some decks and explanations, real little PDFs). Nothing is saved; remove the argument to use your real data. Only works in Debug builds.
4. Run the tests with ⌘U (no API key or network needed).
5. For the API: Settings (gear icon) > paste your API key > Save > Send Test Request. The account needs API credit (console.anthropic.com > Billing); without it you get "Billing problem … credit balance is too low".

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
    MarkdownParser.swift   Splits Markdown into blocks (headings, lists, tables…)
  Services/
    FileStore.swift        Where imported PDFs live on disk
    SourceImporter.swift   Picked files → SourceMaterial records
    PDFReader.swift        PDFKit: page count, page text, thumbnails
    KeychainStore.swift    API key in the Keychain
    ClaudeClient.swift     Messages API request, SSE stream parsing, errors
    PromptBuilder.swift    A lecture's files + instructions → the prompt
    Explainer.swift        Runs lectures through the API, saves the answers
  Views/
    ProjectListView        Projects: create, rename, delete; Settings link
    NewProjectView         Sheet: name + instructions
    ProjectDetailView      Instructions, schedule, weeks, sources, explanations
    InstructionsEditorView Full-screen instructions editor
    ScheduleEditorView     Weekly slots, semester, skipped days, live preview
    LectureDetailView      One lecture, its Explain section (+ AddLectureView, ExplanationView)
    MarkdownView           Draws MarkdownParser's blocks
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
- `SchedulePlanner` applies a saved schedule to lectures that may already exist. It adds missing days and removes untouched lectures on days no longer scheduled. It keeps anything moved or added by hand (`isManual`) or that has files or explanations. Then it renumbers the lectures.
- **Numbering:** a lecture with a deck keeps the number in the deck's name (`QM4Eng_L07_…` → Lecture 7), because that is the course's own numbering. The other lectures are numbered by date around them, never reusing a deck's number. So when a holiday removes the sixth lecture day, the lecture with deck L07 stays "Lecture 7" and the list simply has no Lecture 6. Without any decks this is plain date order: 1, 2, 3…
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

### Explaining a lecture

**The prompt** (`PromptBuilder`) is the same for both ways of explaining:

- *System prompt:* fixed rules (follow the deck, refer to page numbers, explain every symbol, answer in Markdown) plus the project's instructions. It also asks for maths in plain Unicode (ψ, ħ, ∂ψ/∂t, x²) rather than LaTeX, because the app can't render LaTeX.
- *User message:* the course and lecture heading, then each file's extracted text in its own tag (`<reference>`, `<deck>`, `<notes>`), then the task.
- Files that give no text (scanned slides) are flagged on the lecture screen. A lecture whose files have no text at all is not sent, because Claude would have nothing but the task to go on.
- `build(for:)` reads the PDFs, and a second `build(...)` only assembles strings, so tests can check the exact prompt.

**With the API** (`Explainer`):

- One `Explainer` lives for the whole app, passed down with `.environment`. A run keeps going and stays visible when you leave the screen that started it.
- It is `@Observable`, so views reading `liveText` redraw as each piece arrives. The lecture screen renders the partial answer live; the project screen shows "Lecture 5 · 1 of 3 · writing".
- Lectures run one after another. Each finished answer is saved immediately as an `Explanation` titled "Lecture n".
- The first error stops the run and is shown on the lecture and project screens. The usual causes (no credit, bad key, rate limit) would fail every following lecture too.
- Stop cancels the Task. A half-written answer is not saved, but finished ones are kept.
- "Explain All Ready" asks for confirmation first, because it spends API credit.

**With the Claude app:** "Send to Claude App" opens the share sheet with the whole prompt as one text (system part, `---`, user part), since the Claude app has no separate system-prompt field. "Copy Prompt" puts the same text on the clipboard. After Claude answers there, copy the answer and tap "Paste Explanation". iOS asks "Allow Paste?"; Settings > Lecture-Explainer > Paste from Other Apps > Allow stops the question.

**Rendering:** SwiftUI's `Text` only understands inline Markdown (bold, italic, `code`, links). `MarkdownParser` therefore splits the text into blocks first: headings, paragraphs, bullet and numbered lists (nested), tables, quotes, code blocks and rules. `MarkdownView` draws each block, using `Text`'s inline Markdown inside. Tables and code scroll sideways only when they are wider than the screen. A code block that hasn't been closed yet still renders, which matters while an answer streams in.

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
- the prompt (exact text, empty files, reading real PDFs), the Markdown parser, and the Explainer with a fake answer stream (saving, stopping at the first error, skipping lectures without text)

## Build caches in the project folder

If folders like `ModuleCache.noindex/`, `SDKExplicitPrecompiledModules/` or `Lecture-Explainer-<random>/` appear here, a build used this folder as its DerivedData location (for example `xcodebuild -derivedDataPath .`). They are ignored by git and safe to delete; Xcode recreates what it needs in its normal DerivedData folder.

## License

Not yet chosen. Personal project.
