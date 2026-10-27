# Roadmap

Build in small steps. Each step should run before moving on. Each section matches a GitHub milestone issue.

## 1. Model layer and logic (no UI)

- [ ] `Lecture` type: number, week, status, title, markdown, explainedAt
- [ ] `FileNameParser`: extract lecture number from names like `QM4Eng_L05_...pdf`; classify as deck, derivation notes, or symbols sheet
- [ ] `WeekCalendar`: semester start date, current week, lecture number to week and date (two lectures per week)
- [ ] Unit tests for all of the above, including bad file names

## 2. Static UI

- [ ] Week list with fake data and status pills (Explained, Needs deck, Deck added, Not due yet)
- [ ] Explanation detail screen with placeholder text
- [ ] Light and dark mode check

## 3. PDF import

- [ ] `.fileImporter` for multiple PDFs
- [ ] Assign an unnumbered file to a lecture manually
- [ ] `PDFReader` with PDFKit: page text and page thumbnails
- [ ] Remove an imported file

## 4. Claude API

- [ ] `KeychainStore` for the API key and a settings screen
- [ ] Single request to the Messages API with a hardcoded prompt
- [ ] Streaming response (URLSession bytes, server-sent events)
- [ ] Error handling: invalid key, rate limit, request too large, cancelled
- [ ] Stop button via Task cancellation

## 5. Wire it together

- [ ] Build the prompt from deck text, images, notes and symbols sheet
- [ ] Run all lectures that have decks and are not yet explained
- [ ] Live view while streaming, then save with SwiftData
- [ ] Markdown rendering (headings, tables, code)
- [ ] Copy text button

## 6. Polish

- [ ] Empty states and clear error messages
- [ ] Persist imported PDFs so they do not need re-adding
- [ ] App icon and launch screen
- [ ] Accessibility pass (Dynamic Type, VoiceOver labels)

## Open questions

- Send the PDF directly to the API or extract text and images locally? Check current API docs for limits.
- Bundle the course reference material inside the app, or import it?
