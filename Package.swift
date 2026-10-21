// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "DroidMirror",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DroidMirror", targets: ["DroidMirror"])
    ],
    targets: [
        .executableTarget(
            name: "DroidMirror",
            path: "Sources/DroidMirror"
        ),
        .testTarget(
            name: "DroidMirrorTests",
            dependencies: ["DroidMirror"],
            path: "Tests/DroidMirrorTests"
        )
    ]
)
