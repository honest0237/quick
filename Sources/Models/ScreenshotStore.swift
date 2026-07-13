import AppKit

class ScreenshotItem: Identifiable, ObservableObject {
    let id = UUID()
    let thumbnail: NSImage       // 항상 보유하는 작은 미리보기
    let fileURL: URL
    let date: Date
    let filename: String
    let isImageFile: Bool         // 이미지 파일 여부

    // 일반 파일은 시스템 아이콘을 캐시(작음). 이미지 파일은 원본을 보유하지 않고 필요할 때 로드.
    private let cachedIcon: NSImage?

    /// 원본 이미지. 이미지 파일이면 필요 시점에 디스크에서 로드(메모리 절약),
    /// 일반 파일이면 캐시된 시스템 아이콘.
    var fullImage: NSImage? {
        if let cachedIcon { return cachedIcon }
        return NSImage(contentsOf: fileURL)
    }

    // 이미지 파일용 — 전달된 이미지로 썸네일만 만들고 원본은 버림
    init(image: NSImage, fileURL: URL, date: Date = Date()) {
        self.fileURL = fileURL
        self.date = date
        self.filename = fileURL.lastPathComponent
        self.isImageFile = true
        self.cachedIcon = nil

        let maxW: CGFloat = 300
        let ratio = image.size.height / max(image.size.width, 1)
        let thumbSize = NSSize(width: min(image.size.width, maxW), height: min(image.size.width, maxW) * ratio)
        self.thumbnail = image.resized(to: thumbSize)
    }

    // 일반 파일용 (시스템 아이콘 사용)
    init(fileURL: URL, date: Date = Date()) {
        self.fileURL = fileURL
        self.date = date
        self.filename = fileURL.lastPathComponent
        self.isImageFile = false

        let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
        icon.size = NSSize(width: 128, height: 128)
        self.cachedIcon = icon
        self.thumbnail = icon
    }
}

@MainActor
class ScreenshotStore: ObservableObject {
    static let shared = ScreenshotStore()

    @Published var items: [ScreenshotItem] = []
    @Published var selectedID: UUID?          // 키보드 네비게이션용 선택 항목

    private let maxItems = 50

    // MARK: - 키보드 선택

    var selectedItem: ScreenshotItem? { items.first { $0.id == selectedID } }

    func selectNext() {
        guard !items.isEmpty else { return }
        if let id = selectedID, let i = items.firstIndex(where: { $0.id == id }) {
            selectedID = items[min(i + 1, items.count - 1)].id
        } else { selectedID = items.first?.id }
    }

    func selectPrevious() {
        guard !items.isEmpty else { return }
        if let id = selectedID, let i = items.firstIndex(where: { $0.id == id }) {
            selectedID = items[max(i - 1, 0)].id
        } else { selectedID = items.first?.id }
    }

    func copySelected() {
        if let item = selectedItem { copyToClipboard(item) }
    }

    func removeSelected() {
        guard let item = selectedItem,
              let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        remove(item)
        selectedID = items.isEmpty ? nil : items[min(i, items.count - 1)].id
    }

    private init() {
        loadFromDisk()
    }

    func add(image: NSImage, fileURL: URL) {
        let item = ScreenshotItem(image: image, fileURL: fileURL)
        items.insert(item, at: 0)
        trimAndShow()
        persist()
    }

    func addFile(fileURL: URL) {
        // 이미지 파일이면 이미지로 추가
        let ext = fileURL.pathExtension.lowercased()
        let imageExts = ["png", "jpg", "jpeg", "tiff", "gif", "bmp", "webp", "heic"]

        if imageExts.contains(ext), let image = NSImage(contentsOf: fileURL) {
            add(image: image, fileURL: fileURL)
        } else {
            let item = ScreenshotItem(fileURL: fileURL)
            items.insert(item, at: 0)
            trimAndShow()
            persist()
        }
    }

    private func trimAndShow() {
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        QuickPanelController.shared.showIfNeeded()
    }

    func remove(_ item: ScreenshotItem) {
        items.removeAll { $0.id == item.id }
        persist()
        hideIfEmpty()
    }

    func clearAll() {
        items.removeAll()
        selectedID = nil
        persist()
        hideIfEmpty()
    }

    private func hideIfEmpty() {
        if items.isEmpty {
            QuickPanelController.shared.slideOut()
        }
    }

    func move(_ item: ScreenshotItem, by offset: Int) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let newIdx = min(max(idx + offset, 0), items.count - 1)
        guard newIdx != idx else { return }
        items.remove(at: idx)
        items.insert(item, at: newIdx)
        persist()
    }

    func moveToTop(_ item: ScreenshotItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }), idx != 0 else { return }
        items.remove(at: idx)
        items.insert(item, at: 0)
        persist()
    }

    func moveToBottom(_ item: ScreenshotItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }), idx != items.count - 1 else { return }
        items.remove(at: idx)
        items.append(item)
        persist()
    }

    func copyToClipboard(_ item: ScreenshotItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if item.isImageFile, let image = item.fullImage {
            pb.writeObjects([item.fileURL as NSURL, image])
        } else {
            pb.writeObjects([item.fileURL as NSURL])
        }
    }

    // MARK: - 영속화 (재시작 후에도 선반 유지)

    private struct Entry: Codable {
        let path: String
        let date: Date
        let isImageFile: Bool
    }

    private static let storeURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Quick", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("shelf.json")
    }()

    /// 항목 메타데이터만 디스크에 저장(원본 이미지는 저장하지 않고 파일 경로만 기록).
    private func persist() {
        let entries = items.map { Entry(path: $0.fileURL.path, date: $0.date, isImageFile: $0.isImageFile) }
        let url = Self.storeURL
        DispatchQueue.global(qos: .utility).async {
            guard let data = try? JSONEncoder().encode(entries) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// 시작 시 복원 — 파일이 아직 존재하는 항목만. (패널은 띄우지 않음)
    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: Self.storeURL),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return }

        var restored: [ScreenshotItem] = []
        for entry in entries.prefix(maxItems) {
            let url = URL(fileURLWithPath: entry.path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if entry.isImageFile {
                if let image = NSImage(contentsOf: url) {
                    restored.append(ScreenshotItem(image: image, fileURL: url, date: entry.date))
                }
            } else {
                restored.append(ScreenshotItem(fileURL: url, date: entry.date))
            }
        }
        items = restored
    }
}
