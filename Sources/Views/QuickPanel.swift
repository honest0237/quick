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
        let seconds = QuickSettings.shared.autoHideSeconds
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

        let settings = QuickSettings.shared
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
        let settings = QuickSettings.shared
        switch direction {
        case .left, .right:
            return (settings.panelWidth, screen.height)
        case .bottom:
            return (screen.width, settings.panelHeight)
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

// MARK: - 메인 뷰

struct QuickPanelView: View {
    @ObservedObject var store = ScreenshotStore.shared
    @ObservedObject var updater = UpdateService.shared
    @State private var showSettings = false
    @State private var showChangelog = false
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: DispatchWorkItem?

    var isInSearchMode: Bool { !searchText.isEmpty }

    /// 번들 Info.plist에서 읽어 빌드 버전과 자동 일치 (예: "v1.1.0")
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "v\(v)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                Image(systemName: "bolt.square.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Quick")
                    .font(.title2)
                    .fontWeight(.bold)
                Button(action: {
                    if updater.releases.isEmpty { updater.fetchReleases() }
                    showChangelog.toggle()
                }) {
                    Text(appVersion)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("패치 노트 보기")
                .padding(.top, 6)
                .popover(isPresented: $showChangelog, arrowEdge: .bottom) {
                    ChangelogView()
                }
                if updater.updateAvailable, let latest = updater.latestVersion {
                    Button(action: { updater.openReleasePage() }) {
                        Text("⬆ v\(latest)")
                            .font(.caption2).fontWeight(.semibold)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .foregroundColor(.accentColor)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("업데이트 v\(latest) 받기")
                }
                Spacer()
                if !store.items.isEmpty && !isInSearchMode {
                    Text("\(store.items.count)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(8)
                }
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSettings) {
                    SettingsPopover()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // 검색바
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("파일 검색...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .onChange(of: searchText) { newValue in
                        performSearch(query: newValue)
                    }
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        searchResults = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // 검색 모드 vs 일반 모드
            if isInSearchMode {
                searchResultsView
            } else if store.items.isEmpty {
                emptyState
            } else {
                screenshotList
            }
        }
        .frame(minWidth: 200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
        .onHover { hovering in
            if hovering {
                QuickPanelController.shared.cancelAutoHideTimer()
            } else {
                QuickPanelController.shared.resetAutoHideTimer()
            }
        }
        // 외부에서 파일/이미지 드롭 받기
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTarget) { providers in
            handleDrop(providers: providers)
            return true
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDropTarget ? Color.accentColor : Color.clear, lineWidth: 3)
                .animation(.easeInOut(duration: 0.2), value: isDropTarget)
        )
    }

    @State private var isDropTarget = false

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            // 1) 파일 URL (모든 파일 종류)
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                    guard let urlData = data as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }

                    Task { @MainActor in
                        ScreenshotStore.shared.addFile(fileURL: url)
                    }
                }
            }
            // 2) 이미지 데이터 직접 (다른 앱에서 이미지 드래그)
            else if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let image = object as? NSImage else { return }
                    let tmpDir = FileManager.default.temporaryDirectory
                    let filename = "Quick_\(Int(Date().timeIntervalSince1970)).png"
                    let tmpURL = tmpDir.appendingPathComponent(filename)
                    if let tiff = image.tiffRepresentation,
                       let rep = NSBitmapImageRep(data: tiff),
                       let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: tmpURL)
                    }
                    Task { @MainActor in
                        ScreenshotStore.shared.add(image: image, fileURL: tmpURL)
                    }
                }
            }
        }
    }

    // MARK: - 검색

    private func performSearch(query: String) {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        let task = DispatchWorkItem { [query] in
            SearchService.shared.search(query: query) { results in
                self.searchResults = results
                self.isSearching = false
            }
        }
        searchTask = task
        // 200ms 디바운스 — 타이핑 중 불필요한 검색 방지
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
    }

    private var searchResultsView: some View {
        Group {
            if isSearching {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("검색 중...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if searchResults.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "doc.questionmark")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("결과 없음")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(searchResults) { result in
                            SearchResultRow(result: result)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bolt.square.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("파일을 여기에 드롭하거나\n스크린샷을 찍어보세요")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.callout)
            Text("⌘⇧4 캡처 · 드래그 · \(QuickSettings.shared.toggleHotkey.label) 열고닫기")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var screenshotList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                        ScreenshotCard(item: item, index: index, isSelected: store.selectedID == item.id)
                            .id(item.id)
                    }
                }
                .padding(10)
            }
            .onChange(of: store.selectedID) { id in
                if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }
}

// MARK: - 설정 팝오버

struct SettingsPopover: View {
    @ObservedObject private var app = AppSettings.shared
    @State private var hotkey: ToggleHotkey = QuickSettings.shared.toggleHotkey
    @State private var direction: PanelDirection = QuickSettings.shared.panelDirection
    @State private var autoHide: Double = QuickSettings.shared.autoHideSeconds
    @State private var saveDir: String = AppSettings.shared.saveDirectory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("설정")
                .font(.headline)

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
                .pickerStyle(.segmented)
                .frame(width: 120)
                .labelsHidden()
            }

            // 저장 폴더 (마크업 편집본 저장 위치)
            HStack {
                Text("저장 폴더").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(URL(fileURLWithPath: saveDir).lastPathComponent)
                    .font(.caption).lineLimit(1).truncationMode(.middle)
                    .foregroundColor(.secondary).frame(maxWidth: 90, alignment: .trailing)
                Button("변경") { chooseFolder() }
                    .controlSize(.small)
            }

            Divider()

            // 패널
            HStack {
                Text("열기 단축키").font(.caption).foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $hotkey) {
                    ForEach(ToggleHotkey.allCases) { hk in Text(hk.label).tag(hk) }
                }
                .labelsHidden().frame(width: 130)
                .onChange(of: hotkey) { newValue in
                    QuickSettings.shared.toggleHotkey = newValue
                    globalDelegate?.reregisterGlobalHotKey()
                }
            }

            Text("슬라이드 방향").font(.caption).foregroundColor(.secondary)
            Picker("방향", selection: $direction) {
                ForEach(PanelDirection.allCases, id: \.self) { dir in
                    Text(dir.label).tag(dir)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: direction) { newValue in
                QuickSettings.shared.panelDirection = newValue
            }

            HStack {
                Text("자동 숨김").font(.caption).foregroundColor(.secondary)
                Slider(value: $autoHide, in: 0...10, step: 1)
                    .onChange(of: autoHide) { newValue in
                        QuickSettings.shared.autoHideSeconds = newValue
                    }
                Text(autoHide == 0 ? "끔" : "\(Int(autoHide))초")
                    .font(.caption).frame(width: 30)
            }

            Divider()
            Text("\(hotkey.label) 열기/닫기 · Esc 닫기 · 더블클릭 편집")
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
        panel.directoryURL = URL(fileURLWithPath: saveDir)
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            app.saveDirectory = url.path
            saveDir = url.path
        }
    }
}

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

