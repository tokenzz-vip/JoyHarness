// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JoyHarness",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "JoyHarness", targets: ["JoyHarness"])],
    targets: [
        .executableTarget(name: "JoyHarness", path: "Sources/JoyHarness", exclude: ["Info.plist"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("CoreBluetooth"),
                             .linkedFramework("ApplicationServices"), .linkedFramework("IOKit")]),
        .testTarget(name: "JoyHarnessTests", dependencies: ["JoyHarness"], path: "tests/JoyHarnessTests"),
    ]
)
