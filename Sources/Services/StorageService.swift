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

    // MARK: - 파일 저장

    @discardableResult
    func saveToFile(_ image: NSImage) -> URL? {
        guard settings.saveToFile else { return nil }

        let format = settings.format
        let directory = settings.saveDirectoryURL
        let filename = generateFilename(format: format)
        let fileURL = directory.appendingPathComponent(filename)

        // 디렉토리 생성 (없으면)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        guard let imageData = imageToData(image, format: format) else {
            return nil
        }

        do {
            try imageData.write(to: fileURL)
            return fileURL
        } catch {
            print("Failed to save screenshot: \(error)")
            return nil
        }
    }

    // MARK: - 헬퍼

    private func generateFilename(format: ImageFormat) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        return "Screenshot_\(timestamp).\(format.fileExtension)"
    }

    private func imageToData(_ image: NSImage, format: ImageFormat) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        switch format {
        case .png:
            return bitmap.representation(using: .png, properties: [:])
        case .jpeg:
            return bitmap.representation(using: .jpeg, properties: [
                .compressionFactor: 0.9
            ])
        }
    }
}
