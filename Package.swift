// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Boxmail",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Boxmail", targets: ["Boxmail"]),
        .executable(name: "BoxmailPresentationRenderer", targets: ["BoxmailPresentationRenderer"])
    ],
    targets: [
        .target(name: "BoxmailCore", resources: [.process("Resources")]),
        .executableTarget(name: "Boxmail", dependencies: ["BoxmailCore"]),
        .executableTarget(name: "BoxmailPresentationRenderer"),
        .testTarget(name: "BoxmailCoreTests", dependencies: ["BoxmailCore"])
    ],
    swiftLanguageModes: [.v5]
)
