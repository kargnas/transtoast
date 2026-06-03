// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CopyTranslator",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "CopyTranslatorCore", targets: ["CopyTranslatorCore"]),
        .executable(name: "CopyTranslator", targets: ["CopyTranslator"]),
    ],
    targets: [
        .target(name: "CopyTranslatorCore"),
        .executableTarget(
            name: "CopyTranslator",
            dependencies: ["CopyTranslatorCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .testTarget(
            name: "CopyTranslatorTests",
            dependencies: ["CopyTranslatorCore"]
        ),
    ]
)
