// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Barycenter",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0"),
        .package(url: "https://github.com/raspu/Highlightr.git", exact: "2.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "Barycenter",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Highlightr", package: "Highlightr"),
            ],
            resources: [
                .copy("Resources/marked.min.js"),
                .copy("Resources/github-markdown-dark.min.css"),
            ]
        ),
        .testTarget(
            name: "BarycenterTests",
            dependencies: ["Barycenter"]
        ),
    ]
)
