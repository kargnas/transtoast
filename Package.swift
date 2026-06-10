// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CCTrans",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "CCTransCore", targets: ["CCTransCore"]),
        .executable(name: "CCTrans", targets: ["CCTrans"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0"),
    ],
    targets: [
        .target(name: "CCTransCore"),
        .executableTarget(
            name: "CCTrans",
            dependencies: [
                "CCTransCore",
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
            name: "CCTransTests",
            dependencies: ["CCTransCore"]
        ),
    ]
)
