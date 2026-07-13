import AppKit

/// 메모리 항목 — 예전에 찍은 스크린샷 하나(OCR 전문 색인).
struct MemoryEntry: Codable, Identifiable, Equatable {
    var id: String { path }
    let path: String
    let date: Date
    let title: String     // 내용에서 뽑은 짧은 제목
    let text: String      // OCR 전문(검색용)
}

/// "검색되는 스크린샷 메모리" — 찍은 모든 스샷을 OCR로 색인하고 전문 검색.
/// 선반(ScreenshotStore, 임시)과 별개인 영구 저장소. 100% 로컬.
@MainActor
final class ScreenshotMemory: ObservableObject {
    static let shared = ScreenshotMemory()

    @Published private(set) var entries: [MemoryEntry] = []
    private let maxEntries = 5000   // 색인 상한(메모리/성능 보호)

    private init() { load() }

    // MARK: - 색인 (스샷 도착 시 호출)

    func record(image: NSImage, path: String, date: Date = Date()) {
        guard !entries.contains(where: { $0.path == path }) else { return }
        OCRService.recognizeText(in: image) { [weak self] text in
            guard let self else { return }
            let ocr = text ?? ""
            let title = Self.makeTitle(from: ocr, fallback: (path as NSString).lastPathComponent)
            self.entries.insert(MemoryEntry(path: path, date: date, title: title, text: ocr), at: 0)
            if self.entries.count > self.maxEntries { self.entries.removeLast(self.entries.count - self.maxEntries) }
            self.persist()
        }
    }

    // MARK: - 백필 (설치 전부터 있던 기존 스샷도 색인 → 설치 즉시 검색 가능)

    private var isBackfilling = false

    /// 감시 폴더의 기존 스샷을 최신순으로 색인. 백그라운드·직렬·저우선순위.
    func backfillExisting(limit: Int = 300) {
        guard !isBackfilling else { return }
        let dir = FileWatcherService.shared.screenshotDirectory
        let dedicated = FileWatcherService.isDedicated(dir)
        let indexedPaths = Set(entries.map { $0.path })
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        let candidates = urls
            .filter { FileWatcherService.matchesScreenshot($0.lastPathComponent, dedicated: dedicated) }
            .filter { !indexedPaths.contains($0.path) }
            .sorted { modDate($0) > modDate($1) }
            .prefix(limit)
            .map { $0 }
        guard !candidates.isEmpty else { return }
        isBackfilling = true
        processBackfill(candidates, done: 0)
    }

    private func modDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func processBackfill(_ queue: [URL], done: Int) {
        guard let url = queue.first else {         // 완료
            entries.sort { $0.date > $1.date }     // 최신순 정렬
            persist()
            isBackfilling = false
            return
        }
        let rest = Array(queue.dropFirst())
        let date = modDate(url)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let image = NSImage(contentsOfFile: url.path)   // 저우선순위에서 디코드
            DispatchQueue.main.async {
                guard let self else { return }
                guard let image, !self.entries.contains(where: { $0.path == url.path }) else {
                    self.processBackfill(rest, done: done); return
                }
                OCRService.recognizeText(in: image) { text in
                    let ocr = text ?? ""
                    self.entries.append(MemoryEntry(path: url.path, date: date,
                        title: Self.makeTitle(from: ocr, fallback: url.lastPathComponent), text: ocr))
                    if (done + 1) % 5 == 0 { self.persist() }    // 자주 저장(중단돼도 진행분 유지)
                    self.processBackfill(rest, done: done + 1)   // 직렬 진행
                }
            }
        }
    }

    // MARK: - 검색

    /// 존재하는 파일 중, 모든 토큰이 (제목+OCR+파일명)에 포함되는 항목 (최신순)
    func search(_ query: String, limit: Int = 40) -> [MemoryEntry] {
        let tokens = Self.tokens(query)
        guard !tokens.isEmpty else { return [] }
        return entries
            .filter { Self.matches($0, tokens: tokens) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - 순수 함수 (테스트 대상 — 액터 격리 불필요)

    nonisolated static func tokens(_ query: String) -> [String] {
        query.lowercased().split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
    }

    /// 모든 토큰이 제목/OCR/파일명 중 어딘가에 포함되면 매칭
    nonisolated static func matches(_ entry: MemoryEntry, tokens: [String]) -> Bool {
        let blob = (entry.title + "\n" + entry.text + "\n" + (entry.path as NSString).lastPathComponent).lowercased()
        return tokens.allSatisfy { blob.contains($0) }
    }

    /// OCR 전문에서 짧은 제목 추출 — 가장 그럴듯한 첫 줄(2~40자), 없으면 파일명
    nonisolated static func makeTitle(from text: String, fallback: String) -> String {
        let line = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { $0.count >= 2 && $0.count <= 60 })
        guard let line, !line.isEmpty else { return fallback }
        return line.count > 40 ? String(line.prefix(40)) + "…" : line
    }

    // MARK: - 영속화

    private static let indexURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Quick", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("index.json")
    }()

    private func persist() {
        let snapshot = entries
        let url = Self.indexURL
        DispatchQueue.global(qos: .utility).async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.indexURL),
              let decoded = try? JSONDecoder().decode([MemoryEntry].self, from: data) else { return }
        entries = decoded
    }
}
