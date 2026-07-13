import SwiftUI
import AppKit

// MARK: - 패치 노트(체인지로그)

struct ChangelogView: View {
    @ObservedObject var updater = UpdateService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("패치 노트").font(.headline)
                Spacer()
                Button("GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/honest0237/quick/releases")!)
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

            Divider()

            if updater.isLoadingReleases && updater.releases.isEmpty {
                HStack { Spacer(); ProgressView().scaleEffect(0.8); Spacer() }.padding(24)
            } else if updater.releases.isEmpty {
                Text("릴리스 정보를 불러올 수 없습니다.\n인터넷 연결을 확인하세요.")
                    .font(.caption).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(updater.releases) { rel in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Text("v\(rel.version)").font(.subheadline).fontWeight(.bold)
                                    if rel.version == updater.currentVersion {
                                        Text("현재").font(.caption2)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color.accentColor.opacity(0.2)).cornerRadius(4)
                                    }
                                    Spacer()
                                    Text(rel.date).font(.caption2).foregroundColor(.secondary)
                                }
                                Text(rendered(rel.notes))
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
        .frame(width: 330, height: 400)
    }

    /// 마크다운을 팝오버에 맞게 정리(제목 #·코드펜스 ``` 제거) 후 렌더
    private func rendered(_ notes: String) -> AttributedString {
        let cleaned = notes
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> String? in
                var l = String(line)
                if l.trimmingCharacters(in: .whitespaces) == "```" { return nil }
                if l.hasPrefix("#") {
                    while l.hasPrefix("#") { l.removeFirst() }
                    if l.hasPrefix(" ") { l.removeFirst() }
                }
                return l
            }
            .joined(separator: "\n")
        return (try? AttributedString(
            markdown: cleaned,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(cleaned)
    }
}

