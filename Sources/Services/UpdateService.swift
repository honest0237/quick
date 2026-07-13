import AppKit

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
            var version: String?
            var page: URL?
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = json["tag_name"] as? String {
                version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                page = (json["html_url"] as? String).flatMap { URL(string: $0) }
            }
            Task { @MainActor in
                if let version { self.latestVersion = version }
                if let page { self.releaseURL = page }
                completion?()
            }
        }.resume()
    }

    /// 릴리스 페이지(중앙 링크)를 브라우저로 연다.
    func openReleasePage() {
        let fallback = URL(string: "https://github.com/\(owner)/\(repo)/releases/latest")!
        NSWorkspace.shared.open(releaseURL ?? fallback)
    }

    /// "1.2.0" > "1.1.0" 시맨틱 비교
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
