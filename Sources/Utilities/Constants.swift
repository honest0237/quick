import Foundation

enum AppConstants {
    static let appName = "ScreenCapture"
    static let bundleIdentifier = "com.screencapture.app"
    static let version = "1.0.0"
    static let buildNumber = "1"

    enum Defaults {
        static let saveDirectory = NSHomeDirectory() + "/Desktop"
        static let imageFormat = "png"
        static let previewDuration: TimeInterval = 3.0
        static let captureDelay: UInt64 = 200_000_000 // 200ms in nanoseconds
    }
}
