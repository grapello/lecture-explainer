# Lexia

*Lectures, explained.* Formerly "Lecture Explainer". An iPhone app (Swift / SwiftUI / SwiftData) that turns lecture slide decks into detailed explanations using Claude. It is a native port of a web prototype built for the course *Quantum Mechanics for Engineers*, generalised so any course can be a project.

## What it does

1. **Projects.** One project per course, each with its own instructions for Claude ("explain for an engineering student, derive every step…").
2. **Schedule.** Set the weekly lecture slots (e.g. Tue 10:15 and Thu 14:00), the semester dates and the holidays. The app creates the lectures and groups them by week, highlighting the current week and marking future lectures as "not due yet".
3. **PDF import.** Import decks, derivation notes and a symbols sheet from Files. The lecture number is read from the file name (`QM4Eng_L05_…` → lecture 5) and the file is linked to that lecture automatically.
4. **Explain.** Claude gets the PDFs themselves (the symbols sheet, the lecture's deck and notes), so scanned slides and equations drawn as images come through. There are two ways, using the same prompt:
   - **With the API:** your own Anthropic API key, stored in the Keychain. "Explain with Claude" on a lecture, or ✨ "Explain All Ready" on a project for every lecture with a deck and no explanation yet. The answer streams in word by word, can be stopped, and is saved when it is complete. When the API is busy, Lexia waits and tries again.
   - **With the Claude app:** no key needed, runs on your Claude plan. "Send to Claude App" shares the prompt and the PDFs, Claude answers there, you copy the answer, then "Paste Explanation" on the lecture.
   - Explaining a lecture that already has an explanation asks whether to replace the old one or keep both.
5. **Read.** Explanations are rendered from Markdown with typeset formulas (KaTeX), and can be copied.

## Status

Roadmap steps 1–7 are done: data model, projects, schedule and week list, PDF import and reading, the Claude API client, explaining lectures (API or Claude app) with rendered explanations, and polish (app icon, a Get Started checklist, clearer errors with Try Again, accessibility, project templates). On top of that: PDFs sent to Claude directly, typeset formulas, retries, replace-or-keep, and the new name with a loading screen. Left: the optional calendar export and reminders, and checks on a real iPhone. See [docs/ROADMAP.md](docs/ROADMAP.md).

## Requirements

- A Mac with Xcode and the iOS 27 SDK; the app itself runs on iOS 26 or later (the deployment target)
- An iPhone, or the Xcode iOS Simulator
- An Apple ID (free) to run on your own device. Apps signed this way expire after 7 days and need rebuilding.
- For explaining lectures, either an Anthropic API key (pay-per-use API credit, separate from a Claude subscription) or the Claude app with a Claude plan

## Getting started

1. Clone the repo and open `Lecture-Explainer.xcodeproj`. (The project, target and folders keep their old name; only the app's display name changed. Renaming an Xcode target is easy to get wrong and buys nothing for users.)
2. Pick an iPhone simulator and press Run (⌘R).
3. **Try it with sample data:** Product > Scheme > Edit Scheme > Run > Arguments, add `--sample-data`. The app then starts with an in-memory example course (12 lectures, some decks and explanations, real little PDFs). Nothing is saved; remove the argument to use your real data. Only works in Debug builds.
4. Run the tests with ⌘U (no API key or network needed).
5. For the API: Settings (gear icon) > paste your API key > Save > Send Test Request. The account needs API credit (console.anthropic.com > Billing); without it you get "Your Anthropic account has no API credit left".

### Getting PDFs into the Simulator

Drag a PDF from Finder onto the Simulator window and save it to Files ("On My iPhone") from the sheet that opens. If your Xcode version handles the drop differently, open a PDF in Safari inside the Simulator and use Share > Save to Files. Then use + > Import PDFs in a project.

## How the app is built

### Project layout

```
Lecture-Explainer/
  MyApp.swift            App entry; creates the SwiftData store (or sample data)
  ContentView.swift      Root view: ProjectListView, with the loading screen on top at launch
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
    PromptBuilder.swift    A lecture's PDFs + instructions → the prompt
    Explainer.swift        Runs lectures through the API, retries, saves the answers
    ProjectTemplate.swift  A new project from an old one's instructions and lecture times
  Views/
    ProjectListView        Projects: create, rename, delete; Settings link
    NewProjectView         Sheet: name + instructions, optionally from a template
    ProjectDetailView      Get Started checklist or instructions + schedule; weeks, sources, explanations
    InstructionsEditorView Full-screen instructions editor
    ScheduleEditorView     Weekly slots, semester, skipped days, live preview
    LectureDetailView      One lecture, its Explain section (+ AddLectureView, ExplanationView)
    MathMarkdownView       Markdown + LaTeX → typeset page (web view with KaTeX)
    SplashView             The Lexia loading screen
    LexiaLogo              The logo, drawn in code; also rendered into the app icon
    SourceDetailView       One file: kind, lecture, page thumbnails, text
    SettingsView           API key, model, effort, test request
  Resources/KaTeX/       Bundled KaTeX 0.16.11, marked 12.0.2, fonts, licences,
                         lexia.html (the page) and lexia-render.js (Markdown + maths → HTML)
  Assets.xcassets/AppIcon.appiconset/  The app icon (default, dark, tinted), from LexiaLogo
Lecture-ExplainerTests/   Swift Testing unit tests (one file per area)
scripts/render-app-icon.sh  Renders LexiaLogo into the app icon PNGs
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
- `PDFReader` reads page counts, text and thumbnails with PDFKit for the file screen. Claude doesn't get that text; it gets the PDF (see below), so the Text tab can show less than Claude sees.

### Claude API

There is no official Anthropic SDK for Swift, so `ClaudeClient` calls the Messages API directly:

- `POST https://api.anthropic.com/v1/messages` with headers `x-api-key`, `anthropic-version: 2026-10-21` and `content-type: application/json`.
- Body: `model`, `max_tokens`, `stream: true`, `system` (the project's instructions), `messages`, and `output_config.effort`. The user message is a list of blocks: one `document` block per PDF (`source.type: "base64"`, `media_type: "application/pdf"`, the file name as `title`), then the `text` block, the order the API documentation recommends.
- **PDFs:** the API reads each page as text and as an image. Limits: 128 MB per request, 600 pages (100 when the context window is under 1M tokens), no password-protected files. Each page costs roughly 1,500–3,000 tokens plus the image. Lexia refuses more than about 90 MB of PDFs up front (base64 makes them a third larger). Files that are encrypted only against copying are sent as an unencrypted copy made by PDFKit.
- **Prompt caching:** the last reference PDF carries `cache_control: {"type": "ephemeral"}`. Everything before it (system prompt, symbols sheet) is identical for every lecture of a project. Within a few minutes, "Explain All Ready" therefore reads that part from the cache at a fraction of the price.
- Default model `claude-opus-5-5` at effort `high`. Opus 5.5 always thinks before answering, and effort is how much; `high` suits derivations. Sonnet 5.5 and Haiku 5.5 can be chosen in Settings to save cost.
- `fallbacks: "default"` (beta header `server-side-fallback-2026-07-01`): if the model declines a request, the API re-runs it on a suitable other model inside the same call. Haiku doesn't support this, so the field is left out for Haiku.
- **Streaming:** the reply arrives as Server-Sent Events. `ClaudeStreamEvent.parse` reads each `data:` line: `text_delta` pieces are shown, thinking deltas and pings are skipped, and the `message_delta` stop reason and `error` events are checked. The client exposes this as an `AsyncThrowingStream<String, Error>`.
- **Stopping:** cancel the Task that loops over the stream; that cancels the network request.
- **Errors** become `ClaudeError` with a readable message: invalid key (401), billing (402), permission (403), model not found (404), too large (413), rate limited (429, with `retry-after`), server (500), overloaded (529), declined (`refusal`).

### Explaining a lecture

**The prompt** (`PromptBuilder`) is the same for both ways of explaining:

- *System prompt:* fixed rules (follow the deck, refer to page numbers, explain every symbol, read formulas and diagrams from the page images, answer in Markdown) plus the project's instructions. Maths is asked for in LaTeX: `$…$` inline, `$$…$$` displayed.
- *User message:* the PDFs (references first, then decks, then notes), then the course and lecture heading, a list saying what each attached file is, and the task.
- Files that can't be sent (missing from storage, or needing a password) are flagged on the lecture screen. A lecture with none of its own files is not sent, because Claude would have nothing but the task to go on.
- Decision: earlier versions sent text extracted on the phone. That lost scanned slides, diagrams and equations drawn as images, so the PDFs themselves are sent now. They cost more per lecture.
- `build(for:)` looks at the files, and a second `build(...)` only assembles strings, so tests can check the exact prompt.

**With the API** (`Explainer`):

- One `Explainer` lives for the whole app, passed down with `.environment`. A run keeps going and stays visible when you leave the screen that started it.
- It is `@Observable`, so views reading `liveText` redraw as each piece arrives. The lecture screen renders the partial answer live; the project screen shows "Lecture 5 · 1 of 3 · writing".
- Lectures run one after another. Each finished answer is saved immediately as an `Explanation` titled "Lecture n".
- **Retries:** when the API is overloaded, rate-limited or has a server error, the lecture is tried again after 15 s, 45 s and 120 s, or after the wait the API names in `retry-after`. The screens show "API busy, trying again in 20 s". A broken-off answer starts over, because a stream can't be resumed.
- A connection that drops in the middle of an answer is retried the same way. Being offline is not: it rarely fixes itself within two minutes.
- Any other error, or a busy API after the last retry, stops the run and is shown on the lecture and project screens. The usual causes (no credit, bad key) would fail every following lecture too. The messages say what to do: no credit points to console.anthropic.com and to Send to Claude App as the alternative; a rejected key points to Settings.
- **Try Again** continues a stopped run from the lecture that failed, with the lectures it hadn't reached yet. It doesn't start "Explain All Ready" over, so it never sends a different set of lectures than the one you started.
- **Replace or keep both:** "Explain with Claude" or "Paste Explanation" on a lecture that already has an explanation asks first. "Replace the Old One" deletes the old explanation only after the new one is saved, so a failed request loses nothing. "Keep Both" adds the new one, and older ones can be swiped away later.
- Stop cancels the Task. A half-written answer is not saved, but finished ones are kept.
- "Explain All Ready" asks for confirmation first, because it spends API credit.

**With the Claude app:** "Send to Claude App" opens the system share sheet (`UIActivityViewController`) with the whole prompt as one text (system part, `---`, user part) plus the PDFs. SwiftUI's `ShareLink` can't share a text and several files together. The Claude app has no separate system-prompt field, so both parts travel as one message. "Copy Prompt" copies only the text; the PDFs then have to be attached in Claude by hand. After Claude answers, copy the answer and tap "Paste Explanation". iOS asks "Allow Paste?"; Settings > Lexia > Paste from Other Apps > Allow stops the question.

**Rendering with typeset formulas** (`MathMarkdownView`): iOS can't typeset maths by itself, so explanations are shown in a small web page with [KaTeX](https://katex.org), the formula renderer many websites use, and [marked](https://marked.js.org) for the Markdown. Both are bundled in `Resources/KaTeX/` (pinned versions, MIT licence), so it works offline.

- `lexia-render.js` first takes the formulas (`$…$`, `$$…$$`, `\(…\)`, `\[…\]`) out of the text and puts placeholders in. Otherwise marked would read the `_` and `*` in `x_1 * y_2` as italics. Code is set aside first, so a `$` in code stays text, and so does "costs $5 and $6", which has spaces just inside the dollars. Then marked renders the Markdown, and KaTeX's HTML replaces the placeholders. A formula KaTeX can't read is shown in red as written instead of breaking the page.
- Raw HTML in an explanation is shown as text, and images aren't loaded, because the text comes from Claude or the clipboard. Links open in Safari.
- The page follows light/dark mode and the phone's text size (`font: -apple-system-body`). Wide tables and long equations scroll sideways.
- While an answer streams in, the page re-renders at most every 0.3 s, always with the latest text, so typing doesn't stutter. Inside a list, the page reports its height to the app, so the row grows with the text.
- The KaTeX CSS was changed in one place: its font paths point to the files next to it, because Xcode copies resources flat into the app.

### Loading screen, name and icon

The app is called **Lexia** (`INFOPLIST_KEY_CFBundleDisplayName`). At launch iOS shows its static launch screen, a plain background in the system colour. `SplashView` then starts on the same background and animates in the logo, the name and "Lectures, explained". It fades out after about 1.3 s. With Reduce Motion on, it fades instead of growing. The Keychain entry keeps its old service name "Lecture-Explainer", so keys saved before the rename are still found.

**The logo and the app icon are one view.** `LexiaLogo` draws an open book (SF Symbol `book.pages.fill`) with a spark on a blue-violet gradient. It has two styles: a rounded tile with a shadow for the loading screen, and a full square for the icon (iOS rounds icon corners itself). The icon comes in the three looks iOS offers on the home screen: Default (the gradient), Dark (the gradient moves into the book, on near-black) and Tinted (white on black, which iOS colours with the user's tint).

`scripts/render-app-icon.sh` compiles `LexiaLogo.swift` together with a small renderer for the Mac and writes the three 1024 × 1024 PNGs into `AppIcon.appiconset`. They have no transparency, which the App Store requires of icons. So `LexiaLogo.swift` uses SwiftUI only (no UIKit). After changing the logo, run the script again and commit the PNGs.

### Getting started, errors and templates

- **Get Started:** a new project shows a three-step checklist (instructions, schedule, PDFs), each step ticking off when done and opening the place where it is done. The Instructions and Schedule sections replace it once the project has lectures and files.
- **Errors say what to do next:** import alerts are titled "Imported", "Some Files Failed" or "Import Failed"; "Paste Explanation" with an empty clipboard explains how to copy Claude's answer; a stopped run offers Try Again and Dismiss.
- **Templates:** New Project can "Start From" an existing project, or a project's long-press menu has "Use as Template". `ProjectTemplate` copies the instructions and the weekly lecture times and gives them a semester of the same length starting today; lectures, files and explanations stay with the old project. The new project opens with the schedule editor, to set the real dates.

### Accessibility

- Text follows Dynamic Type everywhere, including the explanation page (`-apple-system-body`) and the loading screen (`@ScaledMetric`). At the accessibility text sizes, lecture rows and week headers stack their parts vertically instead of squeezing them into one line.
- VoiceOver: status icons next to text are hidden (the text says it), checklist steps read as "Import the PDFs, Not done", page thumbnails as "Page 3". KaTeX writes MathML next to its HTML, so VoiceOver can read formulas.
- VoiceOver announces each finished lecture and a stopped run (`AccessibilityNotification.Announcement`), since a run of several lectures takes minutes and the user may be on another screen.

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
- the prompt (exact text, attaching stored PDFs, flagging missing ones, unencrypted copies of copy-protected PDFs) and the request's document blocks with the cache marker
- the Explainer with a fake answer stream: saving, stopping at the first error, retrying a busy API (and giving up), Try Again from the failed lecture, replace vs keep both, lectures without files
- network errors (offline vs dropped connection) and the no-credit message
- import alerts when a file can't be copied
- project templates: what is copied, the new semester's dates, a template without a schedule
- the formula renderer: the same `lexia-render.js` run in JavaScriptCore (no web view), checking typeset maths, Markdown around it, `$` in code and prices, and raw HTML shown as text

## Build caches in the project folder

If folders like `ModuleCache.noindex/`, `SDKExplicitPrecompiledModules/` or `Lecture-Explainer-<random>/` appear here, a build used this folder as its DerivedData location (for example `xcodebuild -derivedDataPath .`). They are ignored by git and safe to delete; Xcode recreates what it needs in its normal DerivedData folder.

## License

Not yet chosen. Personal project. Bundled third-party code: KaTeX and marked, both MIT licensed; their licence files are in `Lecture-Explainer/Resources/KaTeX/`.
