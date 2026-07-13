import SwiftUI
import AppKit
import Carbon
import ServiceManagement

// MARK: - 전역

var globalDelegate: AppDelegate!

@main
struct QuickApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        globalDelegate = AppDelegate()
        app.delegate = globalDelegate
        app.run()
    }
}

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let panelController = QuickPanelController.shared
    private var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        FileWatcherService.shared.startWatching()
        registerGlobalHotKey()

        // 기존 스샷 백필 색인 (설치 즉시 검색 가능하도록, 백그라운드)
        ScreenshotMemory.shared.backfillExisting()

        // 실행 시 업데이트 확인 → 새 버전 있으면 메뉴 갱신
        Task { @MainActor in
            UpdateService.shared.checkForUpdates { [weak self] in self?.rebuildMenu() }
        }

        // 첫 실행이면 안내 창 1회 표시
        if !UserDefaults.standard.bool(forKey: "didShowWelcome") {
            UserDefaults.standard.set(true, forKey: "didShowWelcome")
            WelcomeWindowController.present()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        FileWatcherService.shared.stopWatching()
        unregisterGlobalHotKey()
    }

    // MARK: - 상태바 메뉴

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "bolt.square.fill", accessibilityDescription: "Quick") {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            statusItem.button?.image = img.withSymbolConfiguration(config)
            statusItem.button?.image?.isTemplate = true
        } else {
            statusItem.button?.title = "Q"
        }

        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // 업데이트 알림 (새 버전 있을 때만 상단에 강조 표시)
        if UpdateService.shared.updateAvailable, let latest = UpdateService.shared.latestVersion {
            let item = NSMenuItem(title: "🎉 업데이트 있음: v\(latest)", action: #selector(openReleasePage), keyEquivalent: "")
            item.attributedTitle = NSAttributedString(
                string: "🎉 업데이트 있음: v\(latest)",
                attributes: [.foregroundColor: NSColor.controlAccentColor, .font: NSFont.boldSystemFont(ofSize: 13)])
            menu.addItem(item)
            menu.addItem(NSMenuItem.separator())
        }

        menu.addItem(withTitle: "Quick 패널 열기/닫기  \(AppSettings.shared.toggleHotkey.label)", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())

        // 로그인 시 자동 실행
        let launchItem = NSMenuItem(title: "로그인 시 자동 실행", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "전체 삭제", action: #selector(clearAll), keyEquivalent: "")
        menu.addItem(withTitle: "저장 폴더 열기", action: #selector(openFolder), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quick 소개…", action: #selector(showWelcome), keyEquivalent: "")
        menu.addItem(withTitle: "업데이트 확인…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
    }

    @objc func togglePanel() {
        Task { @MainActor in panelController.toggle() }
    }

    @objc func clearAll() {
        Task { @MainActor in ScreenshotStore.shared.clearAll() }
    }

    @objc func openFolder() {
        NSWorkspace.shared.open(FileWatcherService.shared.screenshotDirectory)
    }

    @objc func showWelcome() {
        WelcomeWindowController.present()
    }

    @objc func openReleasePage() {
        UpdateService.shared.openReleasePage()
    }

    @objc func checkForUpdates() {
        UpdateService.shared.checkForUpdates { [weak self] in
            self?.rebuildMenu()
            if !UpdateService.shared.updateAvailable {
                let alert = NSAlert()
                alert.messageText = "최신 버전입니다"
                alert.informativeText = "현재 v\(UpdateService.shared.currentVersion)가 최신입니다."
                alert.runModal()
            } else {
                UpdateService.shared.openReleasePage()
            }
        }
    }

    // MARK: - 로그인 시 자동 실행

    @objc func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if service.status == .enabled {
                    try service.unregister()
                } else {
                    try service.register()
                }
            } catch {
                NSLog("[Quick] LaunchAtLogin 오류: %@", error.localizedDescription)
            }
        }
        rebuildMenu()
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    // MARK: - 글로벌 단축키 (설정에서 변경 가능)

    private var hotKeyHandlerInstalled = false

    private func registerGlobalHotKey() {
        // 이벤트 핸들러는 앱당 한 번만 설치 (재등록 시 중복 설치 방지)
        if !hotKeyHandlerInstalled {
            var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { (_, _, _) -> OSStatus in
                Task { @MainActor in QuickPanelController.shared.toggle() }
                return noErr
            }, 1, &eventSpec, nil, nil)
            hotKeyHandlerInstalled = true
        }
        installHotKey()
    }

    /// 설정된 단축키로 등록 (기존 것은 먼저 해제)
    private func installHotKey() {
        unregisterGlobalHotKey()

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x51554943) // "QUIC"
        hotKeyID.id = 1

        let hk = AppSettings.shared.toggleHotkey
        let status = RegisterEventHotKey(hk.keyCode, hk.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("[Quick] 글로벌 단축키 등록 실패: %d", status)
        } else {
            NSLog("[Quick] 글로벌 단축키 등록: %@", hk.label)
        }
    }

    /// 설정 변경 시 호출 — 단축키 재등록 + 메뉴 라벨 갱신
    func reregisterGlobalHotKey() {
        installHotKey()
        rebuildMenu()
    }

    private func unregisterGlobalHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
