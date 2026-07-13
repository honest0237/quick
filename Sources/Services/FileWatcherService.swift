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

    private init() {}

    func startWatching() {
        qlog("=== Quick 시작 ===")

        let dir = getScreenshotDirectory()
        watchedDir = dir
        qlog("감시 디렉토리: \(dir.path)")

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
            queue: .global(qos: .userInitiated)
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

    private func handleNewScreenshot(at url: URL) {
        qlog("처리: \(url.lastPathComponent)")

        guard let image = NSImage(contentsOf: url) else {
            qlog("로드 실패, 0.5초 후 재시도")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let image = NSImage(contentsOf: url) else {
                    qlog("최종 실패: \(url.path)")
                    return
                }
                self.processImage(image, url: url)
            }
            return
        }
        processImage(image, url: url)
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
        let lower = name.lowercased()
        let patterns = ["스크린샷", "screenshot", "screen shot", "cleanshot"]
        let extensions = ["png", "jpg", "jpeg", "tiff"]
        return patterns.contains(where: { lower.contains($0) })
            && extensions.contains(where: { lower.hasSuffix($0) })
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
