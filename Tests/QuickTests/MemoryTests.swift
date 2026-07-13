import XCTest
@testable import Quick

final class ScreenshotMemoryTests: XCTestCase {

    private func entry(_ path: String, _ title: String, _ text: String) -> MemoryEntry {
        MemoryEntry(path: path, date: Date(), title: title, text: text)
    }

    func test_matches_allTokensRequired() {
        let e = entry("/x/스크린샷 1.png", "인보이스 4021", "고객 인보이스 4021\n합계 55,000원")
        XCTAssertTrue(ScreenshotMemory.matches(e, tokens: ScreenshotMemory.tokens("인보이스")))
        XCTAssertTrue(ScreenshotMemory.matches(e, tokens: ScreenshotMemory.tokens("인보이스 4021")))
        XCTAssertTrue(ScreenshotMemory.matches(e, tokens: ScreenshotMemory.tokens("합계 55")))
        // 한 토큰이라도 없으면 매칭 실패
        XCTAssertFalse(ScreenshotMemory.matches(e, tokens: ScreenshotMemory.tokens("인보이스 9999")))
    }

    func test_matches_searchesOCRText_notJustFilename() {
        // 파일명엔 없지만 OCR 본문에 있는 단어로 찾을 수 있어야 함 (핵심 차별화)
        let e = entry("/x/Screenshot 2024-01-01.png", "Error: connection refused", "Error: connection refused at line 42")
        XCTAssertTrue(ScreenshotMemory.matches(e, tokens: ScreenshotMemory.tokens("connection refused")))
        XCTAssertTrue(ScreenshotMemory.matches(e, tokens: ScreenshotMemory.tokens("line 42")))
    }

    func test_matches_caseInsensitive_multilingual() {
        let e = entry("/x/a.png", "Rechnung", "Bildschirmfoto Rechnung 2024")
        XCTAssertTrue(ScreenshotMemory.matches(e, tokens: ScreenshotMemory.tokens("RECHNUNG")))
    }

    func test_makeTitle_firstMeaningfulLine() {
        XCTAssertEqual(ScreenshotMemory.makeTitle(from: "인보이스 4021\n합계", fallback: "x.png"), "인보이스 4021")
    }

    func test_makeTitle_fallbackWhenNoText() {
        XCTAssertEqual(ScreenshotMemory.makeTitle(from: "", fallback: "Screenshot.png"), "Screenshot.png")
        XCTAssertEqual(ScreenshotMemory.makeTitle(from: "\n\n", fallback: "S.png"), "S.png")
    }

    func test_makeTitle_truncatesLong() {
        let long = String(repeating: "가", count: 80)
        let title = ScreenshotMemory.makeTitle(from: long, fallback: "x")
        // 60자 초과 라인은 제목 후보에서 제외 → fallback
        XCTAssertEqual(title, "x")
    }

    func test_tokens_splitsOnSpaceAndNewline() {
        XCTAssertEqual(ScreenshotMemory.tokens("  a  b\nc "), ["a", "b", "c"])
        XCTAssertTrue(ScreenshotMemory.tokens("   ").isEmpty)
    }
}
