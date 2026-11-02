// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BrightnessRelay",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "brightness-relay", targets: ["BrightnessRelay"]),
        .executable(name: "brightness-self-test", targets: ["BrightnessSelfTest"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/alin23/MediaKeyTap.git",
            revision: "5b8ee686bc90d917cba4f029b47c2a8541a4f58d"
        ),
        .package(url: "https://github.com/SunKit-Swift/SunKit.git", exact: "2.8.2"),
    ],
    targets: [
        .target(
            name: "CPrivateDisplay",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreDisplay"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("DisplayServices"),
                .linkedFramework("IOKit"),
                .unsafeFlags(["-F/System/Library/PrivateFrameworks"]),
            ]
        ),
        .target(
            name: "BrightnessCore",
            linkerSettings: [
                .linkedFramework("CryptoKit"),
            ]
        ),
        .target(
            name: "BrightnessHardware",
            dependencies: ["BrightnessCore", "CPrivateDisplay"]
        ),
        .executableTarget(
            name: "BrightnessRelay",
            dependencies: [
                "BrightnessCore",
                "BrightnessHardware",
                .product(name: "MediaKeyTap", package: "MediaKeyTap"),
                .product(name: "SunKit", package: "SunKit"),
            ],
            resources: [.copy("Resources/FireflyMenu.png")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("Network"),
            ]
        ),
        .executableTarget(
            name: "BrightnessSelfTest",
            dependencies: ["BrightnessCore"]
        ),
        .testTarget(
            name: "BrightnessCoreTests",
            dependencies: ["BrightnessCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
