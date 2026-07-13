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
}

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("saveDirectory") var saveDirectory: String = NSHomeDirectory() + "/Desktop"
    @AppStorage("imageFormat") var imageFormat: String = ImageFormat.png.rawValue
    @AppStorage("playCaptureSound") var playCaptureSound: Bool = true
    @AppStorage("copyToClipboard") var copyToClipboard: Bool = true

    var format: ImageFormat {
        get { ImageFormat(rawValue: imageFormat) ?? .png }
        set { imageFormat = newValue.rawValue }
    }

    var saveDirectoryURL: URL {
        URL(fileURLWithPath: saveDirectory)
    }

    private init() {}
}
