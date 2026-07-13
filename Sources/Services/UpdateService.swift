import AppKit

/// 릴리스(패치로그) 한 건
struct ReleaseInfo: Identifiable {
    let id = UUID()
    let version: String   // "1.2.0"
    let date: String      // "2026-07-13"
    let notes: String     // 릴리스 노트(markdown)
    let url: URL?
}

/// GitHub Releases 기반 업데이트 확인 (인앱 알림 + 중앙 링크).
/// 자동 설치는 하지 않고, 새 버전이 있으면 릴리스 페이지로 안내한다.
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    // 배포 저장소 — 인증 없이 조회하려면 **공개(public) 저장소**여야 함
    private let owner = "honest0237"
    private let repo  = "quick"

    @Published private(set) var latestVersion: String?
    @Published private(set) var releaseURL: URL?
    @Published private(set) var releases: [ReleaseInfo] = []
    @Published private(set) var isLoadingReleases = false

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var updateAvailable: Bool {
        guard let latest = latestVersion else { return false }
        return Self.isNewer(latest, than: currentVersion)
    }

    private init() {}

    /// 최신 릴리스 조회. 완료 시(성공/실패 무관) completion 호출(메인 스레드).
    func checkForUpdates(completion: (() -> Void)? = nil) {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            completion?(); return
        }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: req) { data, _, _ in
            // let 로 확정(불변) — Task가 var를 캡처하면 엄격한 동시성 검사에서 에러
            let version: String?
            let page: URL?
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = json["tag_name"] as? String {
                version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                page = (json["html_url"] as? String).flatMap { URL(string: $0) }
            } else {
                version = nil
                page = nil
            }
            Task { @MainActor in
                if let version { self.latestVersion = version }
                if let page { self.releaseURL = page }
                completion?()
            }
        }.resume()
    }

    /// 전체 릴리스 목록(패치로그) 조회 — 버전 클릭 시 사용.
    func fetchReleases(completion: (() -> Void)? = nil) {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=20") else {
            completion?(); return
        }
        isLoadingReleases = true
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: req) { data, _, _ in
            var parsed: [ReleaseInfo] = []
            if let data,
               let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for r in arr {
                    let tag = (r["tag_name"] as? String) ?? ""
                    let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                    let notes = (r["body"] as? String) ?? ""
                    let date = String((r["published_at"] as? String ?? "").prefix(10))
                    let page = (r["html_url"] as? String).flatMap { URL(string: $0) }
                    parsed.append(ReleaseInfo(version: version, date: date, notes: notes, url: page))
                }
            }
            let result = parsed   // 불변 스냅샷 — Task 캡처용
            Task { @MainActor in
                self.releases = result
                self.isLoadingReleases = false
                completion?()
            }
        }.resume()
    }

    /// 릴리스 페이지(중앙 링크)를 브라우저로 연다.
    func openReleasePage() {
        let fallback = URL(string: "https://github.com/\(owner)/\(repo)/releases/latest")!
        NSWorkspace.shared.open(releaseURL ?? fallback)
    }

    /// "1.2.0" > "1.1.0" 시맨틱 비교 (pre-release 태그 "1.2.0-beta"도 안전하게 처리)
    /// 순수 함수 — 액터 격리 불필요(테스트 가능하도록 nonisolated)
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        func components(_ s: String) -> [Int] {
            s.split(separator: ".").map { comp in
                Int(comp.prefix(while: { $0.isNumber })) ?? 0   // "0-beta" → 0
            }
        }
        let pa = components(a), pb = components(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
