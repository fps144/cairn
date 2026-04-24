// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Cairn",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CairnApp", targets: ["CairnApp"]),
        .library(name: "CairnCore", targets: ["CairnCore"]),
        .library(name: "CairnStorage", targets: ["CairnStorage"]),
        .library(name: "CairnClaude", targets: ["CairnClaude"]),
        .library(name: "CairnTerminal", targets: ["CairnTerminal"]),
        .library(name: "CairnServices", targets: ["CairnServices"]),
        .library(name: "CairnUI", targets: ["CairnUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.13.0"),
    ],
    targets: [
        .target(name: "CairnCore"),
        .target(name: "CairnStorage", dependencies: ["CairnCore"]),
        .target(name: "CairnClaude", dependencies: ["CairnCore", "CairnStorage"]),
        .target(
            name: "CairnTerminal",
            dependencies: [
                "CairnCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
        .target(name: "CairnServices", dependencies: ["CairnCore", "CairnStorage", "CairnClaude"]),
        .target(name: "CairnUI", dependencies: ["CairnServices", "CairnTerminal"]),
        .executableTarget(name: "CairnApp", dependencies: ["CairnUI"]),
        .testTarget(name: "CairnCoreTests", dependencies: ["CairnCore"]),
    ]
)
