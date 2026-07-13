import AppKit

// 디버그 로그 — 기본 비활성. `QUICK_DEBUG=1 ./Quick` 로 실행할 때만 기록.
// (릴리스에서 스크린샷 파일명이 /tmp에 남지 않도록)
private let logFile = "/tmp/quick_debug.log"
private let quickDebugEnabled = ProcessInfo.processInfo.environment["QUICK_DEBUG"] != nil
func qlog(_ msg: String) {
    guard quickDebugEnabled else { return }
    let ts = DateFormatter()
    ts.dateFormat = "HH:mm:ss.SSS"
    let line = "[\(ts.string(from: Date()))] \(msg)\n"
    if let fh = FileHandle(forWritingAtPath: logFile) {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        fh.closeFile()
    } else {
        FileManager.default.createFile(atPath: logFile, contents: line.data(using: .utf8))
    }
}

class FileWatcherService {
    static let shared = FileWatcherService()

    private var dirSource: DispatchSourceFileSystemObject?
    private(set) var watchedDir: URL?
    private var knownFileNames: Set<String> = []
    private var processedFiles: Set<String> = []
    private var isDedicatedScreenshotDir = false   // 전용 폴더면 확장자만으로 감지(로케일 무관)
    private let watchQueue = DispatchQueue(label: "com.screencapture.app.filewatch")  // 직렬 — Set 접근 직렬화

    private init() {}

    func startWatching() {
        qlog("=== Quick 시작 ===")

        let dir = getScreenshotDirectory()
        watchedDir = dir
        isDedicatedScreenshotDir = Self.isDedicated(dir)
        qlog("감시 디렉토리: \(dir.path) (전용: \(isDedicatedScreenshotDir))")

        // 기존 파일명만 캐싱 (속성 읽지 않음 — 빠름)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        knownFileNames = Set(files)
        qlog("기존 파일 수: \(knownFileNames.count)")

        // DispatchSource — 커널이 변경을 알려줌 (폴링 아님)
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else {
            qlog("디렉토리 열기 실패!")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: watchQueue   // 직렬 큐 → 이벤트 핸들러가 자기 자신과 동시 실행되지 않음
        )

        source.setEventHandler { [weak self] in
            self?.onDirectoryChanged()
        }
        source.setCancelHandler { close(fd) }
        self.dirSource = source
        source.resume()

        qlog("DispatchSource 감시 시작")
    }

    func stopWatching() {
        dirSource?.cancel()
        dirSource = nil
    }

    // MARK: - 변경 감지 (이벤트 기반 — CPU 거의 0)

    private func onDirectoryChanged() {
        guard let dir = watchedDir else { return }

        // 파일명만 빠르게 읽기 (속성 안 읽음)
        guard let currentFiles = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        let currentSet = Set(currentFiles)

        // 새 파일만 추출
        let newFiles = currentSet.subtracting(knownFileNames)
        knownFileNames = currentSet

        for name in newFiles {
            guard isScreenshotFile(name), !processedFiles.contains(name) else { continue }
            processedFiles.insert(name)

            let url = dir.appendingPathComponent(name)
            qlog("감지: \(name)")

            // 메인 스레드에서 0.3초 후 처리 (파일 쓰기 완료 대기)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.handleNewScreenshot(at: url)
            }
        }
    }

    // MARK: - 스크린샷 처리

    private func handleNewScreenshot(at url: URL, attempt: Int = 0) {
        qlog("처리: \(url.lastPathComponent) (시도 \(attempt))")

        // 큰/느린 스크린샷(4K·레티나)은 아직 쓰는 중일 수 있음 → 최대 6회(총 ~3초) 재시도
        if let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 {
            processImage(image, url: url)
            return
        }
        guard attempt < 6 else {
            qlog("최종 실패: \(url.path)")
            return
        }
        let delay = 0.3 + Double(attempt) * 0.4
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.handleNewScreenshot(at: url, attempt: attempt + 1)
        }
    }

    private func processImage(_ image: NSImage, url: URL) {
        qlog("성공: \(Int(image.size.width))x\(Int(image.size.height))")

        // 설정에 따라 클립보드 복사 (기본 on, 설정에서 끌 수 있음)
        StorageService.shared.copyToClipboard(image)

        Task { @MainActor in
            ScreenshotStore.shared.add(image: image, fileURL: url)
            qlog("패널 추가 완료")
        }

        if AppSettings.shared.playCaptureSound {
            NSSound(named: "Tink")?.play()
        }
    }

    // MARK: - 헬퍼

    private func isScreenshotFile(_ name: String) -> Bool {
        Self.matchesScreenshot(name, dedicated: isDedicatedScreenshotDir)
    }

    /// 스크린샷 파일 판별 (테스트 가능한 순수 함수).
    /// dedicated=전용 폴더면 이미지 확장자만으로 충분(모든 언어). 아니면 파일명 패턴도 요구.
    static func matchesScreenshot(_ name: String, dedicated: Bool) -> Bool {
        let lower = name.lowercased()
        let extensions = ["png", "jpg", "jpeg", "tiff", "heic"]
        guard extensions.contains(where: { lower.hasSuffix($0) }) else { return false }
        if dedicated { return true }

        let patterns = [
            "스크린샷", "화면 기록",                         // 한국어
            "screenshot", "screen shot", "cleanshot",       // 영어 / CleanShot
            "スクリーンショット", "スクリーン",                // 일본어
            "截屏", "截图", "屏幕快照", "螢幕截圖", "截圖",     // 중국어(간체·번체)
            "bildschirmfoto",                               // 독일어
            "capture", "capture d",                         // 프랑스어 / 일반
            "captura",                                      // 스페인어 / 포르투갈어
            "schermata",                                    // 이탈리아어
            "снимок экрана",                                // 러시아어
        ]
        return patterns.contains { lower.contains($0) }
    }

    /// 전용 스크린샷 폴더 여부(일반 폴더면 이름 패턴도 요구해 오탐 방지)
    private static func isDedicated(_ dir: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var common = [home.standardizedFileURL.path]
        for sub in ["Desktop", "Documents", "Downloads", "Pictures"] {
            common.append(home.appendingPathComponent(sub).standardizedFileURL.path)
        }
        return !common.contains(dir.standardizedFileURL.path)
    }

    var screenshotDirectory: URL {
        watchedDir ?? getScreenshotDirectory()
    }

    private func getScreenshotDirectory() -> URL {
        let plistPath = NSHomeDirectory() + "/Library/Preferences/com.apple.screencapture.plist"
        if let data = FileManager.default.contents(atPath: plistPath),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let location = plist["location"] as? String {
            let expanded = NSString(string: location).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }
}
