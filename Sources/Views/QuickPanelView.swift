import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 메인 뷰

struct QuickPanelView: View {
    @ObservedObject var store = ScreenshotStore.shared
    @ObservedObject var updater = UpdateService.shared
    @State private var showSettings = false
    @State private var showChangelog = false
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var memoryResults: [MemoryEntry] = []   // 내 스샷 메모리 검색(OCR)
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
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            memoryResults = []
            isSearching = false
            return
        }
        // 내 스샷 메모리(OCR)는 로컬·즉시 검색
        memoryResults = ScreenshotMemory.shared.search(trimmed)
        // 파일 검색(mdfind)은 디바운스
        isSearching = true
        let task = DispatchWorkItem { [query] in
            SearchService.shared.search(query: query) { results in
                self.searchResults = results
                self.isSearching = false
            }
        }
        searchTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
    }

    private var searchResultsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 3) {
                // 🧠 내 스크린샷 메모리 (OCR로 찾은 것) — 차별화 핵심, 최상단
                if !memoryResults.isEmpty {
                    Text("🧠 내 스크린샷에서 (\(memoryResults.count))")
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.horizontal, 8).padding(.top, 4)
                    ForEach(memoryResults) { entry in
                        MemorySearchRow(entry: entry)
                    }
                }

                // 파일 검색 (mdfind)
                if isSearching {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.6)
                        Text("파일 검색 중…").font(.caption2).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(6)
                } else if !searchResults.isEmpty {
                    Text("파일").font(.caption).foregroundColor(.secondary)
                        .padding(.horizontal, 8).padding(.top, 6)
                    ForEach(searchResults) { result in
                        SearchResultRow(result: result)
                    }
                }

                // 둘 다 비면 결과 없음
                if memoryResults.isEmpty && searchResults.isEmpty && !isSearching {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.questionmark")
                            .font(.system(size: 32)).foregroundColor(.secondary.opacity(0.5))
                        Text("결과 없음").font(.callout).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 44)
                }
            }
            .padding(8)
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
            Text("⌘⇧4 캡처 · 드래그 · \(AppSettings.shared.toggleHotkey.label) 열고닫기")
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

