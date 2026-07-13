import SwiftUI
import AppKit

// MARK: - 스크린샷 카드 (드래그로 순서 변경 + 외부 드래그)

struct ScreenshotCard: View {
    let item: ScreenshotItem
    let index: Int
    var isSelected: Bool = false
    @State private var isHovered = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if item.isImageFile {
                    Image(nsImage: item.thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(6)
                        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                } else {
                    // 일반 파일: 아이콘 + 파일명
                    HStack(spacing: 10) {
                        Image(nsImage: item.thumbnail)
                            .resizable()
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.filename)
                                .font(.callout)
                                .lineLimit(2)
                                .truncationMode(.middle)
                            let fileSize = (try? FileManager.default.attributesOfItem(atPath: item.fileURL.path)[.size] as? Int) ?? 0
                            Text(formatFileSize(fileSize))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(6)
                }

                // 버튼들 (드래그 위에 표시 — 클릭 가능)
                if isHovered {
                    HStack(spacing: 4) {
                        if index > 0 {
                            Button(action: { moveUp() }) {
                                Image(systemName: "chevron.up")
                                    .font(.caption2)
                                    .frame(width: 22, height: 22)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                        }

                        if index < ScreenshotStore.shared.items.count - 1 {
                            Button(action: { moveDown() }) {
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .frame(width: 22, height: 22)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(5)
                            }
                            .buttonStyle(.plain)
                        }

                        Button(action: copyItem) {
                            Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
                                .font(.caption2)
                                .frame(width: 22, height: 22)
                                .background(.ultraThinMaterial)
                                .cornerRadius(5)
                        }
                        .buttonStyle(.plain)

                        Button(action: removeItem) {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .frame(width: 22, height: 22)
                                .background(.ultraThinMaterial)
                                .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(5)
                }
            }

            // 시간
            HStack {
                Text(timeAgo(item.date))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if copied {
                    Text("복사됨!")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.18)
                                 : (isHovered ? Color.secondary.opacity(0.08) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onHover { isHovered = $0 }
        .onDrag {
            if let provider = NSItemProvider(contentsOf: item.fileURL) { return provider }
            if let image = item.fullImage { return NSItemProvider(object: image) }
            return NSItemProvider()
        }
        .onTapGesture(count: 2) { if item.isImageFile { openEditor() } }
        .onTapGesture { Task { @MainActor in ScreenshotStore.shared.selectedID = item.id } }
        .contextMenu {
            Button("클립보드에 복사") { copyItem() }
            if item.isImageFile {
                Button("편집…") { openEditor() }
                Button("텍스트 복사 (OCR)") { runOCR() }
            }
            Button("Finder에서 보기") {
                NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
            }
            Divider()
            Button("맨 위로") { Task { @MainActor in ScreenshotStore.shared.moveToTop(item) } }
            Button("맨 아래로") { Task { @MainActor in ScreenshotStore.shared.moveToBottom(item) } }
            Divider()
            Button("삭제") { removeItem() }
        }
    }

    private func copyItem() {
        Task { @MainActor in
            ScreenshotStore.shared.copyToClipboard(item)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        }
    }

    private func removeItem() {
        Task { @MainActor in ScreenshotStore.shared.remove(item) }
    }

    private func openEditor() {
        Task { @MainActor in MarkupEditorWindowController.present(item: item) }
    }

    private func runOCR() {
        guard let image = item.fullImage else { return }
        OCRService.recognizeText(in: image) { text in
            guard let text, !text.isEmpty else {
                NSSound(named: "Basso")?.play()   // 인식된 텍스트 없음
                return
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            NSSound(named: "Glass")?.play()        // 복사 완료
        }
    }

    private func moveUp() {
        Task { @MainActor in ScreenshotStore.shared.move(item, by: -1) }
    }

    private func moveDown() {
        Task { @MainActor in ScreenshotStore.shared.move(item, by: 1) }
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "방금" }
        if seconds < 3600 { return "\(seconds / 60)분 전" }
        if seconds < 86400 { return "\(seconds / 3600)시간 전" }
        return "\(seconds / 86400)일 전"
    }

    private func formatFileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}

