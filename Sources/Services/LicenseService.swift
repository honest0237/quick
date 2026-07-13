import Foundation

// MARK: - 기능 정의

enum Feature: String, CaseIterable {
    case fullScreenCapture
    case areaCapture
    case windowCapture
    // 향후 확장용
    // case imageEditing
    // case ocrExtraction
    // case screenRecording
    // case cloudSync
}

// MARK: - 라이선스 프로바이더 프로토콜

protocol LicenseProvider {
    func isFeatureUnlocked(_ feature: Feature) -> Bool
    var licenseType: LicenseType { get }
}

enum LicenseType: String {
    case free
    case pro
    case trial
}

// MARK: - 기본 구현 (모든 기능 활성화)

class FreeLicenseProvider: LicenseProvider {
    func isFeatureUnlocked(_ feature: Feature) -> Bool {
        // 현재는 모든 기능 무료 활성화
        return true
    }

    var licenseType: LicenseType { .free }
}

// MARK: - 라이선스 서비스

class LicenseService {
    static let shared = LicenseService()

    private var provider: LicenseProvider = FreeLicenseProvider()

    private init() {}

    func isUnlocked(_ feature: Feature) -> Bool {
        provider.isFeatureUnlocked(feature)
    }

    var currentLicenseType: LicenseType {
        provider.licenseType
    }

    // 나중에 프로바이더 교체 가능
    func setProvider(_ newProvider: LicenseProvider) {
        provider = newProvider
    }
}
