// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Linkroute",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (rule matching, profile parsing) — unit tested.
        .target(name: "LinkrouteCore"),
        // The menu bar app itself (AppKit + SwiftUI).
        .executableTarget(name: "Linkroute", dependencies: ["LinkrouteCore"]),
        .testTarget(name: "LinkrouteCoreTests", dependencies: ["LinkrouteCore"]),
    ]
)
