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
    targets: [
        .target(name: "TransToastCore"),
        .executableTarget(
            name: "TransToast",
            dependencies: ["TransToastCore"],
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
