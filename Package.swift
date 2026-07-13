// swift-tools-version:5.9
import PackageDescription

// build.sh는 .app 번들 제작용으로 유지. 이 Package.swift는 `swift test`(회귀 테스트)용.
let package = Package(
    name: "Quick",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Quick",
            path: "Sources"
        ),
        .testTarget(
            name: "QuickTests",
            dependencies: ["Quick"],
            path: "Tests/QuickTests"
        ),
    ]
)
