import AppKit

struct SearchResult: Identifiable {
    let id = UUID()
    let fileURL: URL
    let filename: String
    let modDate: Date
    let fileSize: Int
    let icon: NSImage
    let isImage: Bool
}

class SearchService {
    static let shared = SearchService()
    private init() {}

    private let imageExts = Set(["png", "jpg", "jpeg", "tiff", "gif", "bmp", "webp", "heic", "svg"])

    /// Everything 스타일 파일 검색
    func search(query: String, limit: Int = 50, completion: @escaping ([SearchResult]) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            completion([])
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // 검색어를 공백으로 분리 — "보고서 pdf" → 둘 다 포함하는 파일
            let keywords = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            // mdfind -name: 빠른 파일명 부분 매칭
            let firstKeyword = keywords.first ?? trimmed
            let paths = self.mdfindName(firstKeyword)

            let fm = FileManager.default
            var results: [SearchResult] = []

            for path in paths {
                guard results.count < limit * 2 else { break }

                let url = URL(fileURLWithPath: path)
                let filename = url.lastPathComponent
                let lowerFilename = filename.lowercased()

                // 숨김 파일, 시스템 폴더 제외
                if filename.hasPrefix(".") { continue }
                if path.contains("/.") { continue }
                if path.contains("/Library/") && !path.contains("/Mobile Documents/") { continue }
                if path.contains("/.Trash/") { continue }
                if path.contains("/node_modules/") { continue }
                if path.contains("/build/") && path.contains(".app/") { continue }

                // 모든 키워드가 파일명에 포함되는지 확인
                let matchesAll = keywords.allSatisfy { lowerFilename.contains($0.lowercased()) }
                guard matchesAll else { continue }

                guard let attrs = try? fm.attributesOfItem(atPath: path) else { continue }
                let modDate = attrs[.modificationDate] as? Date ?? Date.distantPast
                let fileSize = attrs[.size] as? Int ?? 0

                let ext = url.pathExtension.lowercased()
                let isImage = self.imageExts.contains(ext)

                let icon = NSWorkspace.shared.icon(forFile: path)
                icon.size = NSSize(width: 32, height: 32)

                results.append(SearchResult(
                    fileURL: url,
                    filename: filename,
                    modDate: modDate,
                    fileSize: fileSize,
                    icon: icon,
                    isImage: isImage
                ))
            }

            // 최근 수정순 정렬
            results.sort { $0.modDate > $1.modDate }
            let trimmed = Array(results.prefix(limit))

            DispatchQueue.main.async {
                completion(trimmed)
            }
        }
    }

    /// mdfind -name: macOS Spotlight 기반 빠른 파일명 검색
    private func mdfindName(_ query: String) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-name", query]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
}
