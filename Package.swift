// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Boxmail",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Boxmail", targets: ["Boxmail"])],
    targets: [
        .target(name: "BoxmailCore"),
        .executableTarget(name: "Boxmail", dependencies: ["BoxmailCore"]),
        .testTarget(name: "BoxmailCoreTests", dependencies: ["BoxmailCore"])
    ],
    swiftLanguageModes: [.v5]
)
