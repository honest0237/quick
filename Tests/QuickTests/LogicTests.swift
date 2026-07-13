import XCTest
@testable import Quick

final class VersionCompareTests: XCTestCase {
    func test_basic() {
        XCTAssertTrue(UpdateService.isNewer("1.2.4", than: "1.2.3"))
        XCTAssertFalse(UpdateService.isNewer("1.2.3", than: "1.2.3"))
        XCTAssertFalse(UpdateService.isNewer("1.0.9", than: "1.1.0"))
    }
    func test_numericNotLexical() {
        XCTAssertTrue(UpdateService.isNewer("1.10.0", than: "1.9.0"))
        XCTAssertTrue(UpdateService.isNewer("2.0", than: "1.9.9"))
    }
    func test_preReleaseTagsAreSafe() {
        XCTAssertFalse(UpdateService.isNewer("1.2.0-beta", than: "1.2.0"))
        XCTAssertFalse(UpdateService.isNewer("1.2.0", than: "1.2.0-beta"))
        XCTAssertTrue(UpdateService.isNewer("1.3.0-rc1", than: "1.2.0"))
    }
}

final class ScreenshotDetectionTests: XCTestCase {
    func test_dedicatedFolder_acceptsAnyImage_allLocales() {
        // 전용 폴더면 이름 무관, 확장자만 맞으면 스크린샷으로 취급
        XCTAssertTrue(FileWatcherService.matchesScreenshot("Bildschirmfoto 2024.png", dedicated: true))
        XCTAssertTrue(FileWatcherService.matchesScreenshot("スクリーンショット.png", dedicated: true))
        XCTAssertTrue(FileWatcherService.matchesScreenshot("anything.heic", dedicated: true))
    }
    func test_desktopFallback_matchesLocalePrefixes() {
        XCTAssertTrue(FileWatcherService.matchesScreenshot("스크린샷 2024.png", dedicated: false))       // KR
        XCTAssertTrue(FileWatcherService.matchesScreenshot("Screenshot 2024.png", dedicated: false))     // EN
        XCTAssertTrue(FileWatcherService.matchesScreenshot("Bildschirmfoto.png", dedicated: false))       // DE
        XCTAssertTrue(FileWatcherService.matchesScreenshot("スクリーンショット.png", dedicated: false))    // JA
        XCTAssertTrue(FileWatcherService.matchesScreenshot("截屏2024.png", dedicated: false))             // ZH
    }
    func test_desktopFallback_rejectsNonScreenshots() {
        XCTAssertFalse(FileWatcherService.matchesScreenshot("vacation_photo.png", dedicated: false))
        XCTAssertFalse(FileWatcherService.matchesScreenshot("logo.jpg", dedicated: false))
    }
    func test_rejectsNonImages() {
        XCTAssertFalse(FileWatcherService.matchesScreenshot("notes.txt", dedicated: true))
        XCTAssertFalse(FileWatcherService.matchesScreenshot("Screenshot.pdf", dedicated: false))
    }
}
