import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 패널 컨트롤러 (슬라이딩 애니메이션)

@MainActor
class QuickPanelController {
    static let shared = QuickPanelController()
    private var panel: NSPanel?
    private var isAnimating = false
    private var autoHideTimer: Timer?
    private init() {}

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible {
            slideOut()
        } else {
            slideIn()
            panel?.makeKey()   // 명시적으로 열 때만 키 입력 활성화(Esc·방향키). 자동 표시는 포커스 안 뺏음
        }
    }

    func showIfNeeded() {
        if !isVisible { slideIn() }
        startAutoHideTimer()
    }

    func resetAutoHideTimer() {
        startAutoHideTimer()
    }

    func cancelAutoHideTimer() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    private func startAutoHideTimer() {
        autoHideTimer?.invalidate()
        let seconds = AppSettings.shared.autoHideSeconds
        guard seconds > 0 else { return }
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            Task { @MainActor in
                let ctrl = QuickPanelController.shared
                guard let panel = ctrl.panel else { return }
                let mouseLocation = NSEvent.mouseLocation
                if !panel.frame.contains(mouseLocation) {
                    ctrl.slideOut()
                } else {
                    ctrl.startAutoHideTimer()
                }
            }
        }
    }

    func slideIn() {
        guard !isAnimating else { return }
        isAnimating = true

        let settings = AppSettings.shared
        let direction = settings.panelDirection
        let screen = Self.activeScreen()   // 커서가 있는 화면(멀티모니터 대응)
        let visible = screen.visibleFrame

        let (panelW, panelH) = panelSize(direction: direction, screen: visible)
        let startFrame = offscreenFrame(direction: direction, screen: visible, w: panelW, h: panelH)
        let endFrame = onscreenFrame(direction: direction, screen: visible, w: panelW, h: panelH)

        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
            panel.setFrame(startFrame, display: false)
        } else {
            panel = createPanel(frame: startFrame)
            self.panel = panel
        }

        // 투명하게 시작
        panel.alphaValue = 0.0
        panel.orderFront(nil)

        // macOS 스타일 spring 애니메이션: 빠르게 들어오고 끝에서 감속
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.0, 0.3, 1.0)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(endFrame, display: true)
            panel.animator().alphaValue = 1.0
        }, completionHandler: { [weak self] in
            Task { @MainActor in self?.isAnimating = false }
        })
    }

    func slideOut() {
        guard !isAnimating, let panel = panel else { return }
        isAnimating = true

        // 조용하게 페이드 아웃
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            panel.alphaValue = 1.0
            Task { @MainActor in self?.isAnimating = false }
        })
    }

    // MARK: - 프레임 계산

    /// 현재 커서가 위치한 화면 (없으면 주 화면)
    static func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }

    private func panelSize(direction: PanelDirection, screen: NSRect) -> (CGFloat, CGFloat) {
        let settings = AppSettings.shared
        switch direction {
        case .left, .right:
            return (CGFloat(settings.panelWidth), screen.height)
        case .bottom:
            return (screen.width, CGFloat(settings.panelHeight))
        }
    }

    private func offscreenFrame(direction: PanelDirection, screen: NSRect, w: CGFloat, h: CGFloat) -> NSRect {
        switch direction {
        case .right:
            return NSRect(x: screen.maxX, y: screen.minY, width: w, height: h)
        case .left:
            return NSRect(x: screen.minX - w, y: screen.minY, width: w, height: h)
        case .bottom:
            return NSRect(x: screen.minX, y: screen.minY - h, width: w, height: h)
        }
    }

    private func onscreenFrame(direction: PanelDirection, screen: NSRect, w: CGFloat, h: CGFloat) -> NSRect {
        switch direction {
        case .right:
            return NSRect(x: screen.maxX - w, y: screen.minY, width: w, height: h)
        case .left:
            return NSRect(x: screen.minX, y: screen.minY, width: w, height: h)
        case .bottom:
            return NSRect(x: screen.minX, y: screen.minY, width: w, height: h)
        }
    }

    // MARK: - 패널 생성

    private func createPanel(frame: NSRect) -> NSPanel {
        let panel = QuickKeyPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Quick"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.isMovableByWindowBackground = false
        panel.isMovable = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
        panel.hasShadow = true

        let hostingView = NSHostingView(rootView: QuickPanelView())
        panel.contentView = hostingView

        // 닫기 버튼 = 슬라이드 아웃
        panel.delegate = PanelDelegate.shared

        return panel
    }
}

// MARK: - 패널 delegate (닫기 → 슬라이드 아웃)

class PanelDelegate: NSObject, NSWindowDelegate {
    static let shared = PanelDelegate()
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        Task { @MainActor in QuickPanelController.shared.slideOut() }
        return false
    }
}

// MARK: - 키보드 조작 패널 (Esc 닫기 · ↑↓ 이동 · ⏎/⌘C 복사 · ⌫ 삭제)

final class QuickKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    // Esc → 닫기 (텍스트필드에서 눌러도 responder chain 타고 올라옴 → 안정적)
    override func cancelOperation(_ sender: Any?) {
        Task { @MainActor in QuickPanelController.shared.slideOut() }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: Task { @MainActor in ScreenshotStore.shared.selectPrevious() }  // ↑
        case 125: Task { @MainActor in ScreenshotStore.shared.selectNext() }      // ↓
        case 36:  Task { @MainActor in ScreenshotStore.shared.copySelected() }    // ⏎ 복사
        case 51, 117: Task { @MainActor in ScreenshotStore.shared.removeSelected() } // ⌫ 삭제
        default:
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers == "c" {
                Task { @MainActor in ScreenshotStore.shared.copySelected() }        // ⌘C 복사
            } else {
                super.keyDown(with: event)
            }
        }
    }
}

