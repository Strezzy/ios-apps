import XCTest
@testable import Rift

final class RevealTests: XCTestCase {
    func testBurstIsSpreadWithoutChangingText() {
        var b = RevealBuffer(); b.ingest("Beautiful words appear softly.", at: 10, animated: true)
        XCTAssertEqual(b.visibleCount(at: 10), 1)
        XCTAssertEqual(b.plainText, "Beautiful words appear softly.")
        XCTAssertLessThanOrEqual(b.glyphs.last!.birth, 10.18)
        XCTAssertTrue(b.isSettled(at: 11))
    }
    func testEmojiAndCombiningMarksAreNotSplit() {
        var b = RevealBuffer(); let text = "👩🏽‍💻 café 🇺🇸 e\u{301}"
        b.ingest(text, at: 1, animated: true)
        XCTAssertEqual(b.glyphs.count, text.count); XCTAssertEqual(b.plainText, text)
        b.ingest("e", at: 2, animated: true); b.ingest("e\u{301}", at: 2.01, animated: true)
        XCTAssertEqual(b.glyphs.count, 1)
    }
    func testOldLettersDoNotReplay() {
        var b = RevealBuffer(); b.ingest("Hello", at: 1, animated: true)
        let births = b.glyphs.map(\.birth)
        b.ingest("Hello again", at: 2, animated: true)
        XCTAssertEqual(Array(b.glyphs.prefix(5).map(\.birth)), births)
    }
    func testRepeatedBurstsStayWithinLatencyBudget() {
        var b = RevealBuffer(), text = ""
        for i in 0..<500 {
            let now = 1 + Double(i) * 0.03
            text += "more "
            b.ingest(text, at: now, animated: true)
            XCTAssertLessThanOrEqual(b.glyphs.last!.birth, now + RevealBuffer.maximumLead)
            XCTAssertEqual(b.plainText, text)
        }
    }
    func testReducedMotionAndSavedMessagesAreImmediate() {
        var b = RevealBuffer(); b.ingest("No animation", at: 3, animated: false)
        XCTAssertEqual(b.visibleCount(at: 3), b.glyphs.count); XCTAssertTrue(b.isSettled(at: 3))
    }
    func testCancellationCanFlushWithoutLosingGeneratedText() {
        var b = RevealBuffer(); b.ingest("Partial reply", at: 5, animated: true); b.revealImmediately(at: 5)
        XCTAssertEqual(b.plainText, "Partial reply"); XCTAssertTrue(b.isSettled(at: 5))
    }
    func testRevisedSuffixDoesNotLeaveStaleLetters() {
        var b = RevealBuffer(); b.ingest("Hello wrong suffix", at: 1, animated: true)
        b.ingest("Hello corrected", at: 2, animated: true)
        XCTAssertEqual(b.plainText, "Hello corrected")
        b.ingest("", at: 3, animated: true); XCTAssertTrue(b.isSettled(at: 3)); XCTAssertEqual(b.visibleCount(at: 3), 0)
    }
}
