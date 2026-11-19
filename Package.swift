// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JoyHarness",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "JoyHarness", targets: ["JoyHarness"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .executableTarget(name: "JoyHarness",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/JoyHarness", exclude: ["Info.plist"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("CoreBluetooth"),
                             .linkedFramework("ApplicationServices"), .linkedFramework("IOKit"),
                             .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "JoyHarnessTests", dependencies: ["JoyHarness"], path: "tests/JoyHarnessTests"),
    ]
)
