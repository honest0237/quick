import Foundation

enum PanelDirection: String, CaseIterable {
    case right = "right"
    case left = "left"
    case bottom = "bottom"

    var label: String {
        switch self {
        case .right: return "오른쪽"
        case .left: return "왼쪽"
        case .bottom: return "아래"
        }
    }
}

class QuickSettings {
    static let shared = QuickSettings()
    private let defaults = UserDefaults.standard

    private init() {}

    var panelDirection: PanelDirection {
        get {
            let raw = defaults.string(forKey: "panelDirection") ?? "right"
            return PanelDirection(rawValue: raw) ?? .right
        }
        set {
            defaults.set(newValue.rawValue, forKey: "panelDirection")
        }
    }

    var panelWidth: CGFloat {
        get { CGFloat(defaults.double(forKey: "panelWidth").nonZero ?? 320) }
        set { defaults.set(Double(newValue), forKey: "panelWidth") }
    }

    var panelHeight: CGFloat {
        get { CGFloat(defaults.double(forKey: "panelHeight").nonZero ?? 300) }
        set { defaults.set(Double(newValue), forKey: "panelHeight") }
    }

    /// 자동 숨김 시간 (초). 0이면 자동 숨김 안 함.
    var autoHideSeconds: Double {
        get {
            let val = defaults.object(forKey: "autoHideSeconds") as? Double
            return val ?? 3.0
        }
        set { defaults.set(newValue, forKey: "autoHideSeconds") }
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
