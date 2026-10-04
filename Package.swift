// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentMonitor",
    platforms: [.macOS("27.0")],
    targets: [
        .target(name: "AgentMonitorCore"),
        .executableTarget(
            name: "AgentMonitor",
            dependencies: ["AgentMonitorCore"]
        ),
        .executableTarget(
            name: "AgentMonitorBridge",
            dependencies: ["AgentMonitorCore"]
        ),
        // Assertion-based checks. (Full Xcode would allow an XCTest target;
        // Command Line Tools ship neither XCTest nor swift-testing, so this runs
        // as a plain executable: `swift run MonitorCheck`.)
        .executableTarget(
            name: "MonitorCheck",
            dependencies: ["AgentMonitorCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
