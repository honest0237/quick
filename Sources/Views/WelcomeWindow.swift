import SwiftUI
import AppKit

// MARK: - 첫 실행 안내 창

@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private static var current: WelcomeWindowController?

    static func present() {
        if let c = current {
            c.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let c = WelcomeWindowController()
        current = c
        c.showWindow(nil)
        c.window?.center()
        c.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Quick 소개"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: WelcomeView { [weak self] in self?.window?.close() })
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) { Self.current = nil }
}

// MARK: - 안내 내용

struct WelcomeView: View {
    var onStart: () -> Void

    private var hotkey: String { AppSettings.shared.toggleHotkey.label }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "bolt.square.fill")
                    .font(.system(size: 52))
                    .foregroundColor(.accentColor)
                Text("Quick")
                    .font(.largeTitle).fontWeight(.bold)
                Text("메뉴바에 사는 스크린샷 선반이에요")
                    .foregroundColor(.secondary)
            }
            .padding(.top, 30).padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 16) {
                row("camera.viewfinder", "스크린샷을 찍으면 (⌘⇧4) 자동으로 선반에 모여요")
                row("macwindow", "\(hotkey) 로 선반을 열고 닫아요 · Esc로 닫기")
                row("arrow.up.forward.app", "항목을 다른 앱으로 끌어다 놓아요 (드래그 아웃)")
                row("pencil.tip.crop.circle", "이미지를 더블클릭하면 자르기·가리기·화살표로 편집")
                row("doc.text.viewfinder", "우클릭 → 텍스트 복사(OCR)도 돼요")
                row("menubar.arrow.up.rectangle", "메뉴바 오른쪽 위 아이콘에서 설정·종료")
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 16)

            Text("메뉴바에서 이 안내를 언제든 다시 열 수 있어요.")
                .font(.caption2).foregroundColor(.secondary)

            Button(action: onStart) {
                Text("시작하기").frame(maxWidth: .infinity).fontWeight(.semibold)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 28).padding(.top, 10).padding(.bottom, 24)
        }
        .frame(width: 440, height: 560)
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3).foregroundColor(.accentColor)
                .frame(width: 26, alignment: .center)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
