import AppKit

class StorageService {
    static let shared = StorageService()
    private let settings = AppSettings.shared
    private init() {}

    // MARK: - 클립보드 복사

    func copyToClipboard(_ image: NSImage) {
        guard settings.copyToClipboard else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}
