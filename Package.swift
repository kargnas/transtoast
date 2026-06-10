// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TransToast",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "TransToastCore", targets: ["TransToastCore"]),
        .executable(name: "TransToast", targets: ["TransToast"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0"),
    ],
    targets: [
        .target(name: "TransToastCore"),
        .executableTarget(
            name: "TransToast",
            dependencies: [
                "TransToastCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .testTarget(
            name: "TransToastTests",
            dependencies: ["TransToastCore"]
        ),
    ]
)
