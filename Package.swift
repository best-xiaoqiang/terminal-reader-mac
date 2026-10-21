// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "TerminalReader",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "TerminalReader", targets: ["TerminalReaderApp"])],
    targets: [.executableTarget(name: "TerminalReaderApp")]
)
