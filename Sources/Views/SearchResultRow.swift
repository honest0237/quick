import SwiftUI
import AppKit

// MARK: - 검색 결과 행

struct SearchResultRow: View {
    let result: SearchResult
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: result.icon)
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.filename)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(formatDate(result.modDate))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(formatSize(result.fileSize))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isHovered {
                // Quick에 추가 버튼
                Button(action: addToQuick) {
                    Image(systemName: "plus.circle")
                        .font(.body)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Quick에 추가")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isHovered ? Color.secondary.opacity(0.08) : Color.clear)
        .cornerRadius(6)
        .onHover { isHovered = $0 }
        .onDrag {
            return NSItemProvider(contentsOf: result.fileURL) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Quick에 추가") { addToQuick() }
            Button("Finder에서 보기") {
                NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
            }
            Button("클립보드에 복사 (경로)") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.fileURL.path, forType: .string)
            }
        }
    }

    private func addToQuick() {
        Task { @MainActor in
            ScreenshotStore.shared.addFile(fileURL: result.fileURL)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "오늘 HH:mm"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "어제 HH:mm"
        } else {
            formatter.dateFormat = "M/d"
        }
        return formatter.string(from: date)
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}

