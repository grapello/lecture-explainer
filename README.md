# Lecture Explainer

An iPhone app (Swift / SwiftUI) that turns lecture slide decks into detailed explanations using Claude. It is a native port of a web prototype built for the course *Quantum Mechanics for Engineers*.

## What it does

1. Import lecture PDFs (slide decks, derivation notes, a symbols sheet).
2. The lecture number is read from the file name (for example `QM4Eng_L05_...` is lecture 5).
3. A week-by-week list shows which lectures are explained, need a deck, or are not due yet (two lectures per week).
4. One button sends each deck to Claude, streams the explanation live, and saves it.
5. Read, copy and revisit explanations later, in light or dark mode.

## Status

Planning. No code yet. See [docs/ROADMAP.md](docs/ROADMAP.md) for the build order.

## Requirements

- A Mac with Xcode (free from the Mac App Store)
- An iPhone, or the Xcode iOS Simulator
- An Apple ID (free) to run on your own device. Apps signed this way expire after 7 days and need rebuilding.
- An Anthropic API key (pay-per-use, separate from a Claude subscription)

## Getting started

1. Clone the repo.
2. In Xcode: File > New > Project > iOS > App. Choose SwiftUI and SwiftData. Save it inside this folder.
3. Run on the Simulator to check it builds.

## API key handling

The app never contains a key. The user pastes their own key into a settings screen and it is stored in the iOS Keychain. Do not commit keys, `.xcconfig` secrets, or `.env` files. The `.gitignore` already excludes common secret file names.

## Project layout (planned)

```
QMLectureExplainer/
  Models/      Lecture, Explanation (SwiftData)
  Services/    PDFReader, ClaudeClient, KeychainStore
  Views/       WeekListView, LectureRow, ExplanationView, SettingsView
  Utilities/   FileNameParser, WeekCalendar
QMLectureExplainerTests/
docs/
```

## License

Not yet chosen. Personal project.
