// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DevarDesktop",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "DevarDesktop", targets: ["DevarDesktop"]),
    ],
    targets: [
        .executableTarget(
            name: "DevarDesktop",
            resources: [
                .copy("Resources/desktop_bridge.py"),
                .copy("Resources/devar-logo-mark.png"),
            ]
        ),
    ]
)
