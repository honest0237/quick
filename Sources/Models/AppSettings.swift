import SwiftUI
import Carbon

// MARK: - 열거형

enum ImageFormat: String, CaseIterable, Identifiable {
    case png = "png"
    case jpeg = "jpeg"

    var id: String { rawValue }
    var displayName: String { self == .png ? "PNG" : "JPEG" }
    var fileExtension: String { rawValue }
}

/// 패널 슬라이드 방향
enum PanelDirection: String, CaseIterable {
    case right, left, bottom

    var label: String {
        switch self {
        case .right:  return "오른쪽"
        case .left:   return "왼쪽"
        case .bottom: return "아래"
        }
    }
}

/// 패널 토글 전역 단축키 (⌘Q 종료·한글 입력전환 ⌃Space/⌃⌥Space와 겹치지 않는 것들)
enum ToggleHotkey: String, CaseIterable, Identifiable {
    case optionSpace, shiftCmdSpace, optionCmdV, optionQ

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

// MARK: - 통합 설정 (모든 설정을 한 곳에서, SwiftUI 바인딩 가능)

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private init() {}

    // 저장·동작
    @AppStorage("saveDirectory")   var saveDirectory: String = NSHomeDirectory() + "/Desktop"
    @AppStorage("imageFormat")     var imageFormat: String = ImageFormat.png.rawValue
    @AppStorage("playCaptureSound") var playCaptureSound: Bool = true
    @AppStorage("copyToClipboard")  var copyToClipboard: Bool = true

    // 패널 (@AppStorage는 String-RawRepresentable enum을 직접 저장 가능 → 뷰에서 바로 바인딩)
    @AppStorage("panelDirection")  var panelDirection: PanelDirection = .right
    @AppStorage("toggleHotkey")    var toggleHotkey: ToggleHotkey = .optionSpace
    @AppStorage("autoHideSeconds") var autoHideSeconds: Double = 3.0
    @AppStorage("panelWidth")      var panelWidth: Double = 320
    @AppStorage("panelHeight")     var panelHeight: Double = 300

    var format: ImageFormat {
        get { ImageFormat(rawValue: imageFormat) ?? .png }
        set { imageFormat = newValue.rawValue }
    }
    var saveDirectoryURL: URL { URL(fileURLWithPath: saveDirectory) }
}
