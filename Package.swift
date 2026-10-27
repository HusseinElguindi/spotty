// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Spotty",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LauncherCore", targets: ["LauncherCore"]),
        .executable(name: "Spotty", targets: ["Spotty"]),
    ],
    targets: [
        // Matching, ranking, learning and the calculator. Foundation only, so it tests anywhere.
        .target(name: "LauncherCore"),
        // The app: AppKit and SwiftUI around LauncherCore.
        .executableTarget(name: "Spotty", dependencies: ["LauncherCore"]),
        .testTarget(name: "LauncherCoreTests", dependencies: ["LauncherCore"]),
    ]
)
