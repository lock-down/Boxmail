// swift-tools-version: 6.0
import PackageDescription
import Foundation

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let localTests: [Target] = [
    .testTarget(name: "BoxmailCoreTests", dependencies: ["BoxmailCore"]),
    .testTarget(name: "BoxmailTests", dependencies: ["Boxmail"])
].filter { FileManager.default.fileExists(atPath: packageRoot.appendingPathComponent("Tests/\($0.name)").path) }

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
        .executableTarget(name: "BoxmailPresentationRenderer")
    ] + localTests,
    swiftLanguageModes: [.v5]
)
