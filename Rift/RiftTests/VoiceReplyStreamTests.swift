import XCTest
@testable import Rift

final class VoiceReplyStreamTests: XCTestCase {
    func testSpeaksCompletedPhraseBeforeGenerationFinishesWithoutRepeatingIt() {
        var stream = VoiceReplyStream()
        XCTAssertEqual(stream.take("Hello there. More", final: false), ["Hello there."])
        XCTAssertTrue(stream.hasSpoken)
        XCTAssertFalse(stream.finished)
        XCTAssertEqual(stream.take("Hello there. More words", final: false), [])
        XCTAssertEqual(stream.take("Hello there. More words", final: true), ["More words"])
        XCTAssertEqual(stream.take("Hello there. More words", final: true), [])
    }
    func testTokenByTokenFilteringHidesReasoningCodeAndLinkDestinations() {
        var stream = VoiceReplyStream(), snapshot = "", spoken: [String] = []
        let text = "<think>Secret reasoning. Never say this.</think>Hello there. Read [this guide](https://example.com/private).\n```swift\nsecretCode()\n```\nDone."
        for character in text {
            snapshot.append(character)
            spoken += stream.take(snapshot, final: false)
            XCTAssertFalse(stream.diverged, "Unstable prefix at: \(snapshot)")
        }
        spoken += stream.take(snapshot, final: true)
        let result = spoken.joined(separator: " ")
        XCTAssertEqual(result, "Hello there. Read this guide. Code is shown in the chat. Done.")
        XCTAssertFalse(result.contains("Secret"))
        XCTAssertFalse(result.contains("https"))
        XCTAssertFalse(result.contains("secretCode"))
    }
    func testDecimalsAbbreviationsAndUnicodeStayIntact() {
        var stream = VoiceReplyStream()
        XCTAssertEqual(stream.take("Dr. Chen measured 3.14 units. Next", final: false), ["Dr. Chen measured 3.14 units."])
        XCTAssertEqual(stream.take("Dr. Chen measured 3.14 units. Next 🌸 sentence。", final: false), ["Next 🌸 sentence。"])
        XCTAssertEqual(stream.take("Dr. Chen measured 3.14 units. Next 🌸 sentence。", final: true), [])
    }
    func testLongUnpunctuatedReplyStartsAtAWordBoundary() {
        var stream = VoiceReplyStream()
        let text = String(repeating: "a gentle flowing response ", count: 20).trimmingCharacters(in: .whitespaces)
        let first = stream.take(text, final: false)
        XCTAssertFalse(first.isEmpty)
        XCTAssertLessThanOrEqual(first[0].count, 96)
        let all = first + stream.take(text, final: true)
        XCTAssertEqual(all.joined(separator: " "), text)
    }
    func testRewrittenSpokenPrefixStopsRatherThanRepeatingOrSkippingText() {
        var stream = VoiceReplyStream()
        XCTAssertEqual(stream.take("First sentence. Next", final: false), ["First sentence."])
        XCTAssertEqual(stream.take("Changed sentence. Next", final: false), [])
        XCTAssertTrue(stream.diverged)
        XCTAssertFalse(stream.canResumeListening(queued: 0, generating: false))
    }
    func testMicrophoneWaitsForBothGenerationAndSpeechToFinish() {
        var stream = VoiceReplyStream()
        _ = stream.take("First sentence. Next", final: false)
        XCTAssertFalse(stream.canResumeListening(queued: 0, generating: true))
        XCTAssertFalse(stream.canResumeListening(queued: 0, generating: false))
        _ = stream.take("First sentence. Next", final: true)
        XCTAssertFalse(stream.canResumeListening(queued: 1, generating: false))
        XCTAssertFalse(stream.canResumeListening(queued: 0, generating: true))
        XCTAssertTrue(stream.canResumeListening(queued: 0, generating: false))
    }
    func testEmptyAnswerAndFreshTurnDoNotReuseSpeech() {
        var stream = VoiceReplyStream()
        XCTAssertEqual(stream.take("<think>Only reasoning", final: true), [])
        XCTAssertFalse(stream.hasSpoken)
        stream = VoiceReplyStream()
        XCTAssertEqual(stream.take("New turn.", final: true), ["New turn."])
    }
}
