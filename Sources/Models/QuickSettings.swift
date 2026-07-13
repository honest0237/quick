import Foundation
import Carbon

/// 패널 토글 전역 단축키 (사용자 선택). ⌘Q(종료)·한글 입력전환(⌃Space, ⌃⌥Space)과 겹치지 않는 것들.
enum ToggleHotkey: String, CaseIterable, Identifiable {
    case optionSpace    // ⌥Space (기본)
    case shiftCmdSpace  // ⇧⌘Space
    case optionCmdV     // ⌥⌘V
    case optionQ        // ⌥Q (기존)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .optionSpace:   return "⌥Space"
        case .shiftCmdSpace: return "⇧⌘Space"
        case .optionCmdV:    return "⌥⌘V"
        case .optionQ:       return "⌥Q"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .optionSpace, .shiftCmdSpace: return UInt32(kVK_Space)
        case .optionCmdV:                  return UInt32(kVK_ANSI_V)
        case .optionQ:                     return UInt32(kVK_ANSI_Q)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .optionSpace:   return UInt32(optionKey)
        case .shiftCmdSpace: return UInt32(shiftKey | cmdKey)
        case .optionCmdV:    return UInt32(optionKey | cmdKey)
        case .optionQ:       return UInt32(optionKey)
        }
    }
}

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

    /// 패널 토글 전역 단축키 (기본 ⌥Space)
    var toggleHotkey: ToggleHotkey {
        get { ToggleHotkey(rawValue: defaults.string(forKey: "toggleHotkey") ?? "") ?? .optionSpace }
        set { defaults.set(newValue.rawValue, forKey: "toggleHotkey") }
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
