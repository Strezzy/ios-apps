import XCTest
@testable import Rift

final class RevealTests: XCTestCase {
    func testBurstsAreSpreadAndLeadIsBounded() {
        var schedule = RevealSchedule()
        schedule.ingest("Hello, this arrived in one very large backend chunk.", now: 10, animate: true)
        XCTAssertEqual(schedule.text, "Hello, this arrived in one very large backend chunk.")
        XCTAssertGreaterThan(Set(schedule.arrivals).count, 1)
        XCTAssertLessThanOrEqual(schedule.arrivals.last!, 10 + RevealSchedule.maximumLead)
    }
    func testOldCharactersNeverReplay() {
        var schedule = RevealSchedule()
        schedule.ingest("Hello", now: 1, animate: true)
        let old = schedule.arrivals
        schedule.ingest("Hello there", now: 2, animate: true)
        XCTAssertEqual(Array(schedule.arrivals.prefix(5)), old)
    }
    func testLargeBurstsCatchUpWithoutSecondsOfDelay() {
        var schedule = RevealSchedule()
        schedule.ingest(String(repeating: "a", count: 10_000), now: 0, animate: true)
        XCTAssertEqual(schedule.arrivals.count, 10_000)
        XCTAssertLessThanOrEqual(schedule.completion, 0.18 + 0.28)
    }
    func testEmojiAndCombiningMarksRemainWhole() {
        let text = "👨‍👩‍👧‍👦 cafe\u{301} 日本語 مرحباً"
        var schedule = RevealSchedule()
        schedule.ingest(text, now: 1, animate: true)
        XCTAssertEqual(schedule.text, text)
        XCTAssertEqual(schedule.arrivals.count, text.count)
        XCTAssertEqual(schedule.characters.first, "👨‍👩‍👧‍👦")
    }
    func testCorrectionsAndShorterSnapshotsStayExact() {
        var schedule = RevealSchedule()
        schedule.ingest("Hello world", now: 1, animate: true)
        schedule.ingest("Hello 🌸", now: 2, animate: true)
        XCTAssertEqual(schedule.text, "Hello 🌸")
        XCTAssertEqual(schedule.arrivals.count, "Hello 🌸".count)
    }
    func testStopFlushesWithoutChangingText() {
        var schedule = RevealSchedule()
        schedule.ingest("Stop here", now: 1, animate: true)
        schedule.finishImmediately(now: 1.01)
        XCTAssertEqual(schedule.text, "Stop here")
        XCTAssertLessThan(schedule.completion, 1.01)
    }
    func testHistoryIsInstant() {
        var schedule = RevealSchedule()
        schedule.ingest("Saved conversation", now: 20, animate: false)
        XCTAssertLessThan(schedule.completion, 20)
    }
    func testEmptyOutputIsSafe() {
        var schedule = RevealSchedule()
        schedule.ingest("", now: 1, animate: true)
        XCTAssertEqual(schedule.text, "")
        XCTAssertTrue(schedule.arrivals.isEmpty)
    }
}
