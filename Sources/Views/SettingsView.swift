import SwiftUI
import AppKit

// MARK: - 설정 팝오버 (AppSettings에 직접 바인딩 — @State 복사 불필요)

struct SettingsPopover: View {
    @ObservedObject private var app = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("설정").font(.headline)

            // 동작
            Toggle("새 스크린샷 자동 복사", isOn: $app.copyToClipboard)
            Toggle("감지 시 소리", isOn: $app.playCaptureSound)

            Divider()

            // 저장 형식
            HStack {
                Text("저장 형식").font(.caption).foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $app.imageFormat) {
                    ForEach(ImageFormat.allCases) { fmt in
                        Text(fmt.displayName).tag(fmt.rawValue)
                    }
                }
                .pickerStyle(.segmented).frame(width: 120).labelsHidden()
            }

            // 저장 폴더 (마크업 편집본 저장 위치)
            HStack {
                Text("저장 폴더").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(URL(fileURLWithPath: app.saveDirectory).lastPathComponent)
                    .font(.caption).lineLimit(1).truncationMode(.middle)
                    .foregroundColor(.secondary).frame(maxWidth: 90, alignment: .trailing)
                Button("변경") { chooseFolder() }.controlSize(.small)
            }

            Divider()

            // 열기 단축키
            HStack {
                Text("열기 단축키").font(.caption).foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $app.toggleHotkey) {
                    ForEach(ToggleHotkey.allCases) { hk in Text(hk.label).tag(hk) }
                }
                .labelsHidden().frame(width: 130)
                .onChange(of: app.toggleHotkey) { _ in globalDelegate?.reregisterGlobalHotKey() }
            }

            // 슬라이드 방향
            Text("슬라이드 방향").font(.caption).foregroundColor(.secondary)
            Picker("방향", selection: $app.panelDirection) {
                ForEach(PanelDirection.allCases, id: \.self) { dir in Text(dir.label).tag(dir) }
            }
            .pickerStyle(.segmented).labelsHidden()

            // 자동 숨김
            HStack {
                Text("자동 숨김").font(.caption).foregroundColor(.secondary)
                Slider(value: $app.autoHideSeconds, in: 0...10, step: 1)
                Text(app.autoHideSeconds == 0 ? "끔" : "\(Int(app.autoHideSeconds))초")
                    .font(.caption).frame(width: 30)
            }

            Divider()
            Text("\(app.toggleHotkey.label) 열기/닫기 · Esc 닫기 · 더블클릭 편집")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(16)
        .frame(width: 260)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: app.saveDirectory)
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            app.saveDirectory = url.path
        }
    }
}
