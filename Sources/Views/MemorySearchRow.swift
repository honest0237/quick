import SwiftUI
import AppKit

/// 메모리 검색 결과 한 줄 — 예전에 찍은 스샷(OCR로 찾은 것). 썸네일+제목+날짜, 드래그아웃/선반추가.
struct MemorySearchRow: View {
    let entry: MemoryEntry
    @State private var thumb: NSImage?
    @State private var isHovered = false

    private var fileURL: URL { URL(fileURLWithPath: entry.path) }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let thumb {
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo").foregroundColor(.secondary.opacity(0.5))
                }
            }
            .frame(width: 46, height: 34).clipped().cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title).font(.callout).lineLimit(1).truncationMode(.tail)
                Text(formatDate(entry.date)).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            if isHovered {
                Button(action: addToShelf) {
                    Image(systemName: "plus.circle").font(.body).foregroundColor(.accentColor)
                }
                .buttonStyle(.plain).help("선반에 추가")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(isHovered ? Color.secondary.opacity(0.08) : .clear)
        .cornerRadius(6)
        .onHover { isHovered = $0 }
        .onAppear(perform: loadThumb)
        .onDrag { NSItemProvider(contentsOf: fileURL) ?? NSItemProvider() }
        .contextMenu {
            Button("선반에 추가") { addToShelf() }
            Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }
        }
    }

    private func loadThumb() {
        guard thumb == nil else { return }
        let path = entry.path
        DispatchQueue.global(qos: .userInitiated).async {
            guard let full = NSImage(contentsOfFile: path) else { return }
            DispatchQueue.main.async { self.thumb = full.resized(to: NSSize(width: 92, height: 68)) }
        }
    }

    private func addToShelf() {
        Task { @MainActor in ScreenshotStore.shared.addFile(fileURL: fileURL) }
    }

    private func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(date) { f.dateFormat = "오늘 HH:mm" }
        else if cal.isDateInYesterday(date) { f.dateFormat = "어제 HH:mm" }
        else { f.dateFormat = "M/d" }
        return f.string(from: date)
    }
}
