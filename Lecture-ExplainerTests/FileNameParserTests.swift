//
//  FileNameParserTests.swift
//  Lexia
//
//  Created by Gabriel Rapello on 28.10.26.
//


import Testing
@testable import Lecture_Explainer

struct FileNameParserTests {
    @Test func symbolsSheetIsReference() {
        let result = FileNameParser.parse("Symbols_v1.pdf")
        #expect(result == ParsedFileName(kind: .reference, lectureNumber: nil, slide: nil))
    }
    @Test func deckWithLectureNumber() {
            let result = FileNameParser.parse("QM4Eng_L199_Intro.pdf")
            #expect(result == ParsedFileName(kind: .deck, lectureNumber: nil, slide: nil))
        }
    @Test func DerivationIsNotes() {
            let result = FileNameParser.parse("DerivationL02S22.pdf")
            #expect(result == ParsedFileName(kind: .notes, lectureNumber: 2, slide: 22))
        }

    // Names the parser should read
    @Test(arguments: [
        ("QM4Eng_L05_Intro.pdf",          ParsedFileName(kind: .deck,  lectureNumber: 5,  slide: nil)),
        ("qm4eng_l12_waves.pdf",          ParsedFileName(kind: .deck,  lectureNumber: 12, slide: nil)),  // lower case
        ("Derivation_L03_S07.pdf",        ParsedFileName(kind: .notes, lectureNumber: 3,  slide: 7)),    // underscore before S
        ("QM4Eng_L05_Slides.pdf",         ParsedFileName(kind: .deck,  lectureNumber: 5,  slide: nil)),  // "S" not followed by digits
    ])
    func readableNames(name: String, expected: ParsedFileName) {
        #expect(FileNameParser.parse(name) == expected)
    }

    // Bad or unusual names: no crash, and nil wherever the parser can't be sure
    @Test(arguments: [
        ("",                              ParsedFileName(kind: .deck,  lectureNumber: nil, slide: nil)),
        ("notes.pdf",                     ParsedFileName(kind: .deck,  lectureNumber: nil, slide: nil)),
        ("QM4Eng_Intro.pdf",              ParsedFileName(kind: .deck,  lectureNumber: nil, slide: nil)), // the 4 in QM4Eng isn't a lecture
        ("Derivation_L2026S22.pdf",       ParsedFileName(kind: .notes, lectureNumber: nil, slide: nil)), // too large: slide dropped too
    ])
    func badNamesGiveNil(name: String, expected: ParsedFileName) {
        #expect(FileNameParser.parse(name) == expected)
    }
}
