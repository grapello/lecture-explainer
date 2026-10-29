//
//  FileNameParserTests.swift
//  Lecture-Explainer
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
            #expect(result == ParsedFileName(kind: .notes, lectureNumber: 2, slide: nil))
        }
}
