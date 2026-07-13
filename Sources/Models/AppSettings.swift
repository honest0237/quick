import SwiftUI

enum ImageFormat: String, CaseIterable, Identifiable {
    case png = "png"
    case jpeg = "jpeg"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        }
    }

    var fileExtension: String { rawValue }

    var utType: String {
        switch self {
        case .png: return "public.png"
        case .jpeg: return "public.jpeg"
        }
    }
}

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("saveDirectory") var saveDirectory: String = NSHomeDirectory() + "/Desktop"
    @AppStorage("imageFormat") var imageFormat: String = ImageFormat.png.rawValue
    @AppStorage("showPreview") var showPreview: Bool = true
    @AppStorage("playCaptureSound") var playCaptureSound: Bool = true
    @AppStorage("copyToClipboard") var copyToClipboard: Bool = true
    @AppStorage("saveToFile") var saveToFile: Bool = true

    // 단축키 설정 (기본값)
    @AppStorage("hotkeyFullScreen") var hotkeyFullScreen: String = "cmd+shift+3"
    @AppStorage("hotkeyArea") var hotkeyArea: String = "cmd+shift+4"
    @AppStorage("hotkeyWindow") var hotkeyWindow: String = "cmd+shift+5"

    var format: ImageFormat {
        get { ImageFormat(rawValue: imageFormat) ?? .png }
        set { imageFormat = newValue.rawValue }
    }

    var saveDirectoryURL: URL {
        URL(fileURLWithPath: saveDirectory)
    }

    private init() {}
}
